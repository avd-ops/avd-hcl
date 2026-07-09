#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Az.Accounts'; ModuleVersion = '2.0.0' }
#Requires -Modules @{ ModuleName = 'Az.Resources'; ModuleVersion = '6.0.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.0.0' }

<#
.SYNOPSIS
    Takes a greenfield subscription + Entra tenant from zero to "ready for Lab Kit."
    Run once, up front, by choice. (CLAUDE.md Section 19.)

.DESCRIPTION
    "Setup once, verify every time." This script is the setup half. It remediates
    exactly one thing -- resource provider registration -- because that is the only
    prerequisite it can safely change on someone's behalf. Everything else it
    inspects and reports, because the remedies are procurement decisions, support
    tickets, or tenant-wide security changes that no lab tool should make for you.

    Distinct from Connect-AvdLabContext (Section 3/4), which runs at the start of
    every deployment and only ever checks and fails fast. This runs once.

    THE HEADLINE CHECK IS SECURITY DEFAULTS.
    Entra Kerberos requires the FSLogix storage account app to be excluded from
    MFA. That exclusion is only expressible as a Conditional Access policy, and
    Security Defaults offers no exclusion mechanism at all -- it is on or off.
    Security Defaults is also ON BY DEFAULT for new tenants. So the single most
    likely reason a greenfield run fails is a tenant setting that predates the
    first line of Bicep, and resolving it is a deliberate, tenant-wide decision:
    disable Security Defaults, replace it with Conditional Access (Entra ID P1).
    See Section 6/12/19 and Set-AvdLabFSLogixAuth.ps1, which refuses to proceed.

.NOTES
    REST over cmdlets, deliberately.
    Checks are issued through Invoke-AzRestMethod / Invoke-MgGraphRequest rather
    than Get-AzVMUsage, Get-MgSubscribedSku, and friends. Those cmdlets live in
    Az.Compute, Microsoft.Graph.Identity.SignIns, and
    Microsoft.Graph.Identity.DirectoryManagement -- three more modules a user must
    install before a *prerequisite checker* will run, which is a poor joke. The
    REST endpoints are stable, and this keeps the module surface to the three in
    Section 3's tooling list.

.PARAMETER SubscriptionId
    Target subscription. Passed explicitly so a stale Az context cannot quietly
    prepare the wrong subscription.

.PARAMETER TenantId
    Target Entra tenant. Same reasoning.

.PARAMETER Location
    Azure region, for the quota check. Must match avdlab.bicepparam.

.PARAMETER VmSize
    Session host VM size, for the quota check. Must match avdlab.bicepparam.

.PARAMETER SessionHostCount
    Number of session hosts, for the quota check. Must match avdlab.bicepparam.

.PARAMETER OutputPath
    Optional. Writes the readiness report as JSON alongside the console output.

.EXAMPLE
    ./Initialize-AvdLabPrerequisites.ps1 -SubscriptionId <guid> -TenantId <guid>

.EXAMPLE
    # See what it would register, without registering anything.
    ./Initialize-AvdLabPrerequisites.ps1 -SubscriptionId <guid> -TenantId <guid> -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$SubscriptionId,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$TenantId,

    [string]$Location = 'eastus2',
    [string]$VmSize = 'Standard_D4ads_v5',
    [ValidateRange(1, 50)]
    [int]$SessionHostCount = 3,

    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RequiredProviders = @(
    'Microsoft.DesktopVirtualization'
    'Microsoft.Compute'
    'Microsoft.Network'
    'Microsoft.Storage'
)

# roleTemplateId is stable across every tenant; displayName is not (it is
# localized, and "Company Administrator" still appears in older tenants).
$script:GlobalAdminRoleTemplateId = '62e90394-69f5-4237-9190-012177145e10'

# Eligible licenses for Windows 11 Enterprise multi-session, per the AVD licensing
# doc. Matched on skuPartNumber. Treat as a strong hint, not gospel: a tenant can
# hold entitlement through an agreement this list does not name, which is exactly
# why this check reports rather than blocks.
$script:EligibleSkuPartNumbers = @(
    'SPE_E3'                    # Microsoft 365 E3
    'SPE_E5'                    # Microsoft 365 E5
    'SPE_F1'                    # Microsoft 365 F3
    'SPB'                       # Microsoft 365 Business Premium
    'WIN10_VDA_E3'              # Windows Enterprise E3
    'WIN10_VDA_E5'              # Windows Enterprise E5
    'M365EDU_A3_FACULTY'        # Microsoft 365 A3
    'M365EDU_A3_STUDENT'
    'M365EDU_A3_STUUSEBNFT'     # Student Use Benefit
    'M365EDU_A5_FACULTY'        # Microsoft 365 A5
    'M365EDU_A5_STUDENT'
)

# Dev/Test subscriptions carry AVD access rights for acceptance testing without a
# separate per-user entitlement. quotaId is the only reliable way to detect one.
$script:DevTestQuotaIds = @('MSDN_2014-09-01', 'MSDNDevTest_2014-09-01')

$script:Results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param(
        [Parameter(Mandatory)][string]$Check,
        [Parameter(Mandatory)][ValidateSet('Pass', 'Fixed', 'ActionNeeded', 'Blocker', 'Unknown')][string]$Status,
        [Parameter(Mandatory)][string]$Detail,
        [string]$Action = ''
    )
    $script:Results.Add([pscustomobject]@{
            Check  = $Check
            Status = $Status
            Detail = $Detail
            Action = $Action
        })

    $glyph, $colour = switch ($Status) {
        'Pass' { '[ok]', 'Green' }
        'Fixed' { '[fixed]', 'Green' }
        'ActionNeeded' { '[action]', 'Yellow' }
        'Blocker' { '[BLOCKED]', 'Red' }
        'Unknown' { '[?]', 'DarkGray' }
    }
    Write-Host ('  {0,-10} {1,-32} {2}' -f $glyph, $Check, $Detail) -ForegroundColor $colour
    if ($Action) { Write-Host ('             -> {0}' -f $Action) -ForegroundColor $colour }
}

function Invoke-AzRest {
    <# Returns parsed JSON, or throws with the service's own error text. #>
    param([Parameter(Mandatory)][string]$Path)
    $response = Invoke-AzRestMethod -Path $Path -Method GET
    if ($response.StatusCode -ge 400) {
        throw "Azure REST $Path returned $($response.StatusCode): $($response.Content)"
    }
    $response.Content | ConvertFrom-Json
}

function Get-Value {
    <#
        Reads a field that may legitimately be absent, returning $null instead of
        throwing. Necessary for two reasons that compound: StrictMode makes any
        missing member fatal (for hashtables as well as objects), and the two REST
        helpers return different shapes -- Invoke-MgGraphRequest yields hashtables,
        ConvertFrom-Json yields PSCustomObjects. Handles both.
    #>
    param($Object, [Parameter(Mandatory)][string]$Name)

    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        return $(if ($Object.Contains($Name)) { $Object[$Name] } else { $null })
    }
    $property = $Object.PSObject.Properties[$Name]
    return $(if ($property) { $property.Value } else { $null })
}

# --------------------------------------------------------------------------
# Context
# --------------------------------------------------------------------------
function Assert-Context {
    $azContext = Get-AzContext
    if (-not $azContext -or $azContext.Subscription.Id -ne $SubscriptionId -or $azContext.Tenant.Id -ne $TenantId) {
        Write-Host "  connecting to Azure (subscription $SubscriptionId)..." -ForegroundColor Gray
        Connect-AzAccount -Subscription $SubscriptionId -Tenant $TenantId | Out-Null
        $azContext = Get-AzContext
    }

    if ($azContext.Subscription.Id -ne $SubscriptionId) {
        throw "Connected to subscription $($azContext.Subscription.Id), expected $SubscriptionId."
    }
    Add-Result -Check 'Azure context' -Status Pass -Detail "$($azContext.Subscription.Name) as $($azContext.Account.Id)"

    $mgContext = Get-MgContext
    if (-not $mgContext -or $mgContext.TenantId -ne $TenantId) {
        Write-Host '  connecting to Microsoft Graph...' -ForegroundColor Gray
        Connect-MgGraph -TenantId $TenantId -NoWelcome -Scopes @(
            'Directory.Read.All'      # directory roles, subscribedSkus
            'Policy.Read.All'         # security defaults, conditional access, MDM scope
        )
        $mgContext = Get-MgContext
    }
    Add-Result -Check 'Graph context' -Status Pass -Detail "tenant $($mgContext.TenantId) as $($mgContext.Account)"
}

# --------------------------------------------------------------------------
# 1. Resource providers -- the ONLY thing this script remediates.
# --------------------------------------------------------------------------
function Initialize-ResourceProvider {
    foreach ($provider in $script:RequiredProviders) {
        $state = (Get-AzResourceProvider -ProviderNamespace $provider -ErrorAction SilentlyContinue |
                Select-Object -First 1).RegistrationState

        if ($state -eq 'Registered') {
            Add-Result -Check "Provider $provider" -Status Pass -Detail 'registered'
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($provider, 'Register resource provider')) {
            Add-Result -Check "Provider $provider" -Status ActionNeeded -Detail "state: $state (WhatIf: would register)"
            continue
        }

        # Register-AzResourceProvider is a no-op when already registered, so this
        # is safe to run repeatedly. Registration is async; it can sit in
        # 'Registering' for a minute or two. Not worth blocking on.
        Register-AzResourceProvider -ProviderNamespace $provider | Out-Null
        Add-Result -Check "Provider $provider" -Status Fixed -Detail 'registration requested (async; may show Registering briefly)'
    }
}

# --------------------------------------------------------------------------
# 2. vCPU quota (report only -- an increase is a support request, not an API call)
# --------------------------------------------------------------------------
function Test-VcpuQuota {
    try {
        $skus = Invoke-AzRest -Path ("/subscriptions/$SubscriptionId/providers/Microsoft.Compute/skus" +
            "?api-version=2021-07-01&`$filter=location eq '$Location'")

        $sku = $skus.value | Where-Object { $_.resourceType -eq 'virtualMachines' -and $_.name -eq $VmSize } | Select-Object -First 1
        if (-not $sku) {
            Add-Result -Check 'vCPU quota' -Status Unknown -Detail "VM size $VmSize not offered in $Location" `
                -Action "Pick a size available in $Location, or change the region."
            return
        }

        $vcpuCapability = $sku.capabilities | Where-Object { $_.name -eq 'vCPUs' } | Select-Object -First 1
        $perHost = [int](Get-Value $vcpuCapability 'value')
        if ($perHost -le 0) {
            Add-Result -Check 'vCPU quota' -Status Unknown -Detail "could not determine vCPU count for $VmSize"
            return
        }
        $needed = $perHost * $SessionHostCount
        $family = Get-Value $sku 'family'

        $usages = Invoke-AzRest -Path ("/subscriptions/$SubscriptionId/providers/Microsoft.Compute/locations/$Location/usages" +
            '?api-version=2023-07-01')

        # Two quotas gate a deployment, and a lab hits the family one first:
        # the per-family limit, and the regional total across all families.
        $familyUsage = $usages.value | Where-Object { (Get-Value $_.name 'value') -eq $family } | Select-Object -First 1
        $totalUsage = $usages.value | Where-Object { (Get-Value $_.name 'value') -eq 'cores' } | Select-Object -First 1

        foreach ($usage in @(
                @{ Label = "family $family"; Usage = $familyUsage }
                @{ Label = 'regional total cores'; Usage = $totalUsage }
            )) {
            if (-not $usage.Usage) { continue }
            $available = $usage.Usage.limit - $usage.Usage.currentValue
            $detail = "$($usage.Label): $available of $($usage.Usage.limit) vCPU free, need $needed"

            if ($available -ge $needed) {
                Add-Result -Check 'vCPU quota' -Status Pass -Detail $detail
            }
            else {
                Add-Result -Check 'vCPU quota' -Status ActionNeeded -Detail $detail `
                    -Action 'Request a quota increase now -- approval is not instant and cannot be scripted.'
            }
        }
    }
    catch {
        Add-Result -Check 'vCPU quota' -Status Unknown -Detail "could not read quota: $($_.Exception.Message)"
    }
}

# --------------------------------------------------------------------------
# 3. Licensing (report only -- procurement, not provisioning)
# --------------------------------------------------------------------------
function Test-Licensing {
    # A Dev/Test subscription grants AVD access rights for acceptance testing, so
    # check it before concluding the tenant is unlicensed.
    $isDevTest = $false
    try {
        $subscription = Invoke-AzRest -Path "/subscriptions/$SubscriptionId`?api-version=2022-12-01"
        $quotaId = $subscription.subscriptionPolicies.quotaId
        $isDevTest = $quotaId -in $script:DevTestQuotaIds
        if ($isDevTest) {
            Add-Result -Check 'Win11 multi-session licensing' -Status Pass `
                -Detail "Dev/Test subscription ($quotaId) -- AVD access rights included for testing"
            return
        }
    }
    catch {
        Write-Verbose "Could not read subscription policies: $($_.Exception.Message)"
    }

    try {
        $skus = (Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/subscribedSkus').value
        $held = @($skus | ForEach-Object { $_.skuPartNumber })
        $eligible = @($held | Where-Object { $_ -in $script:EligibleSkuPartNumbers })

        if ($eligible.Count -gt 0) {
            Add-Result -Check 'Win11 multi-session licensing' -Status Pass -Detail "eligible SKU(s): $($eligible -join ', ')"
        }
        elseif ($held.Count -eq 0) {
            Add-Result -Check 'Win11 multi-session licensing' -Status ActionNeeded -Detail 'tenant holds no licenses at all' `
                -Action 'Acquire M365 E3/E5/F3/Business Premium, Windows Enterprise E3/E5, or use a Dev/Test subscription.'
        }
        else {
            Add-Result -Check 'Win11 multi-session licensing' -Status ActionNeeded `
                -Detail "no recognized eligible SKU (tenant holds: $($held -join ', '))" `
                -Action 'Verify entitlement manually -- this list does not cover every agreement type.'
        }
    }
    catch {
        Add-Result -Check 'Win11 multi-session licensing' -Status Unknown -Detail "could not read subscribedSkus: $($_.Exception.Message)"
    }
}

# --------------------------------------------------------------------------
# 4. Security Defaults -- the blocker (see .NOTES)
# --------------------------------------------------------------------------
function Test-SecurityDefaults {
    try {
        $policy = Invoke-MgGraphRequest -Method GET `
            -Uri 'https://graph.microsoft.com/v1.0/policies/identitySecurityDefaultsEnforcementPolicy'

        if (-not $policy.isEnabled) {
            Add-Result -Check 'Security Defaults' -Status Pass -Detail 'disabled -- the storage account app can be excluded from MFA'
            return
        }

        Add-Result -Check 'Security Defaults' -Status Blocker -Detail 'ENABLED -- Entra Kerberos cannot work in this tenant' `
            -Action 'Disable Security Defaults, then create Conditional Access policies (needs Entra ID P1). No script can do this for you.'
    }
    catch {
        Add-Result -Check 'Security Defaults' -Status Unknown -Detail "could not read policy: $($_.Exception.Message)"
    }
}

# --------------------------------------------------------------------------
# 5. Conditional Access -- informational; the exclusion lives here
# --------------------------------------------------------------------------
function Test-ConditionalAccess {
    try {
        $policies = (Invoke-MgGraphRequest -Method GET `
                -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies').value

        $enabled = @($policies | Where-Object { $_.state -eq 'enabled' })
        if ($enabled.Count -eq 0) {
            Add-Result -Check 'Conditional Access' -Status Pass -Detail 'no enabled policies'
            return
        }

        Add-Result -Check 'Conditional Access' -Status ActionNeeded -Detail "$($enabled.Count) enabled polic$(if ($enabled.Count -eq 1){'y'}else{'ies'})" `
            -Action 'Any MFA-for-all-apps policy must exclude the storage account app. Set-AvdLabFSLogixAuth.ps1 -ApplyConditionalAccessExclusion does this.'
    }
    catch {
        # A tenant without Entra ID P1 returns an error here. That is not a
        # failure -- it means CA does not exist to conflict with, which only
        # matters if Security Defaults is also off.
        Add-Result -Check 'Conditional Access' -Status Unknown -Detail 'could not enumerate (tenant may lack Entra ID P1)'
    }
}

# --------------------------------------------------------------------------
# 6. MDM auto-enrollment scope -- informational (Lab Kit stays Intune-free)
# --------------------------------------------------------------------------
function Test-MdmScope {
    try {
        $policies = (Invoke-MgGraphRequest -Method GET `
                -Uri 'https://graph.microsoft.com/v1.0/policies/mobileDeviceManagementPolicies').value

        $scoped = @($policies | Where-Object {
                $appliesTo = Get-Value $_ 'appliesTo'
                $appliesTo -and $appliesTo -ne 'none'
            })
        if ($scoped.Count -eq 0) {
            Add-Result -Check 'MDM auto-enrollment' -Status Pass -Detail 'no user scope configured; session hosts will not enroll'
            return
        }

        $names = ($scoped | ForEach-Object { "$(Get-Value $_ 'displayName') (appliesTo: $(Get-Value $_ 'appliesTo'))" }) -join '; '
        Add-Result -Check 'MDM auto-enrollment' -Status ActionNeeded -Detail $names `
            -Action 'Session hosts will silently enroll into Intune. Not a Lab Kit dependency (Intune is Hard Mode) -- just know before you are on stage.'
    }
    catch {
        Add-Result -Check 'MDM auto-enrollment' -Status Unknown -Detail "could not read MDM policies: $($_.Exception.Message)"
    }
}

# --------------------------------------------------------------------------
# 7. RBAC + Global Admin -- access does not follow from creating the tenant
# --------------------------------------------------------------------------
function Test-Permission {
    $principalId = $null
    try {
        $me = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me'
        $principalId = $me.id

        $roles = (Invoke-MgGraphRequest -Method GET `
                -Uri 'https://graph.microsoft.com/v1.0/me/transitiveMemberOf/microsoft.graph.directoryRole').value

        $isGlobalAdmin = @($roles | Where-Object { $_.roleTemplateId -eq $script:GlobalAdminRoleTemplateId }).Count -gt 0
        if ($isGlobalAdmin) {
            Add-Result -Check 'Global Administrator' -Status Pass -Detail 'held by the signed-in account'
        }
        else {
            Add-Result -Check 'Global Administrator' -Status ActionNeeded `
                -Detail "not held (roles: $(($roles | ForEach-Object { $_.displayName }) -join ', '))" `
                -Action 'Required for the Entra Kerberos app-registration steps (Section 6). Not a Contributor-level operation.'
        }
    }
    catch {
        Add-Result -Check 'Global Administrator' -Status Unknown -Detail "could not read directory roles: $($_.Exception.Message)"
    }

    if (-not $principalId) { return }

    try {
        $scope = "/subscriptions/$SubscriptionId"
        $assignments = @(Get-AzRoleAssignment -ObjectId $principalId -Scope $scope -ErrorAction Stop)
        $roleNames = @($assignments | ForEach-Object { $_.RoleDefinitionName })

        $hasOwner = 'Owner' -in $roleNames
        $hasPair = ('Contributor' -in $roleNames) -and ('User Access Administrator' -in $roleNames)

        if ($hasOwner -or $hasPair) {
            Add-Result -Check 'Subscription RBAC' -Status Pass -Detail ($roleNames -join ', ')
        }
        else {
            Add-Result -Check 'Subscription RBAC' -Status ActionNeeded -Detail "holds: $($roleNames -join ', ')" `
                -Action 'Need Owner, or Contributor + User Access Administrator (the RBAC role assignment for the FSLogix share needs the latter).'
        }
    }
    catch {
        Add-Result -Check 'Subscription RBAC' -Status Unknown -Detail "could not read role assignments: $($_.Exception.Message)"
    }
}

# ==========================================================================

Write-Host "`nAVD Lab Kit -- prerequisite check`n" -ForegroundColor Cyan

Assert-Context

Write-Host "`nRemediating:" -ForegroundColor Cyan
Initialize-ResourceProvider

Write-Host "`nReporting:" -ForegroundColor Cyan
Test-VcpuQuota
Test-Licensing
Test-SecurityDefaults
Test-ConditionalAccess
Test-MdmScope
Test-Permission

# --------------------------------------------------------------------------
$blockers = @($script:Results | Where-Object { $_.Status -eq 'Blocker' })
$actions = @($script:Results | Where-Object { $_.Status -eq 'ActionNeeded' })
$unknowns = @($script:Results | Where-Object { $_.Status -eq 'Unknown' })

Write-Host "`n$('-' * 74)" -ForegroundColor DarkGray
if ($blockers.Count -gt 0) {
    Write-Host "NOT READY -- $($blockers.Count) blocker(s), $($actions.Count) action(s) needed." -ForegroundColor Red
}
elseif ($actions.Count -gt 0) {
    Write-Host "$($actions.Count) action(s) needed before deploying. None are things a script can do for you." -ForegroundColor Yellow
}
else {
    Write-Host 'READY -- no blockers or outstanding actions.' -ForegroundColor Green
}
if ($unknowns.Count -gt 0) {
    Write-Host "$($unknowns.Count) check(s) inconclusive -- verify by hand rather than assuming they passed." -ForegroundColor DarkGray
}
Write-Host "$('-' * 74)`n" -ForegroundColor DarkGray

if ($OutputPath) {
    $report = [pscustomobject]@{
        generatedUtc   = (Get-Date).ToUniversalTime().ToString('o')
        subscriptionId = $SubscriptionId
        tenantId       = $TenantId
        location       = $Location
        vmSize         = $VmSize
        sessionHosts   = $SessionHostCount
        results        = $script:Results
    }
    $directory = Split-Path -Parent $OutputPath
    if ($directory -and -not (Test-Path $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $report | ConvertTo-Json -Depth 6 | Set-Content -Path $OutputPath -Encoding utf8
    Write-Host "Report written to $OutputPath`n" -ForegroundColor Gray
}

# Non-zero on a blocker so this is usable as a gate, not just a wall of text.
# ActionNeeded does not fail: a quota increase in flight is a real state to be in.
if ($blockers.Count -gt 0) { exit 1 }
