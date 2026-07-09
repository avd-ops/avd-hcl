#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.0.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Applications'; ModuleVersion = '2.0.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Identity.SignIns'; ModuleVersion = '2.0.0' }

<#
.SYNOPSIS
    Completes the Entra app-registration configuration that Microsoft Entra Kerberos
    for Azure Files requires, and that ARM/Bicep cannot express.

.DESCRIPTION
    storage.bicep sets `directoryServiceOptions: 'AADKERB'`. Azure responds by
    auto-generating an Entra application named:

        [Storage Account] <storageAccountName>.file.core.windows.net

    That application must then be configured three ways. None are ARM resources;
    all are Microsoft Graph. Deploying storage.bicep without running this script
    leaves you with a share that looks perfectly configured and does not work.

      1. Grant admin consent for the three delegated Microsoft Graph permissions
         the app requests (openid, profile, User.Read), tenant-wide. This is what
         lets users request Entra tokens for the storage account.

      2. Add the `kdc_enable_cloud_group_sids` tag to the application manifest.
         MANDATORY for cloud-only identities, which is exactly what Easy Mode
         uses. Without it, Entra omits cloud-only group SIDs from the Kerberos
         ticket and share permissions granted to an Entra group never resolve.
         This is the step that fails silently: everything looks right until a
         profile fails to load.

      3. Ensure no MFA requirement applies to that application. Kerberos tickets
         are acquired silently during logon; there is no UI to answer an MFA
         prompt. Without this, `net use` against the share returns
         "System error 1327: Account restrictions are preventing this user from
         signing in."

    Step 3 is the one this script cannot always fix, and it refuses to pretend
    otherwise. See the SECURITY DEFAULTS note below.

.NOTES
    SECURITY DEFAULTS IS A HARD BLOCKER, NOT A HURDLE.
    Excluding an application from an MFA requirement is a Conditional Access
    operation, and Conditional Access requires Entra ID P1. Security Defaults is
    all-or-nothing by design -- it exposes no exclusion mechanism for any app or
    user (the sole documented exception is the Directory Synchronization Accounts
    role). So a tenant with Security Defaults enabled cannot host a working
    Entra Kerberos FSLogix share, full stop. The remedy is tenant-level and
    deliberate -- disable Security Defaults and replace it with Conditional
    Access policies that exclude this app -- so this script reports the condition
    and stops rather than silently weakening a tenant's security posture.

    CLOUD-ONLY IDENTITY SUPPORT IS IN PREVIEW.
    Entra Kerberos for cloud-only identities (no on-prem AD DS) is documented as
    Preview as of 2026-07-09. Easy Mode depends on it. Worth knowing before this
    is demoed live or forked by an audience.

.PARAMETER StorageAccountName
    Name of the FSLogix storage account, as output by storage.bicep.

.PARAMETER TenantId
    Entra tenant to operate against. Passed explicitly so a mis-scoped Graph
    session fails fast rather than configuring the wrong tenant.

.PARAMETER StorageSuffix
    File endpoint suffix. Azure Commercial only in v1 (Section 1); GovCloud is a
    parallel variant, not a flag.

.PARAMETER ApplyConditionalAccessExclusion
    Opt-in. Patches every MFA-requiring Conditional Access policy that targets all
    applications so it excludes this storage account app. Off by default: editing
    a tenant's CA policies is not something a lab deployment should do to you
    without being asked. Without it, the script reports which policies need the
    exclusion and leaves them alone.

.EXAMPLE
    ./Set-AvdLabFSLogixAuth.ps1 -StorageAccountName stavdlabfslogix -TenantId <guid> -WhatIf

.EXAMPLE
    ./Set-AvdLabFSLogixAuth.ps1 -StorageAccountName stavdlabfslogix -TenantId <guid> -Verbose
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9]{3,24}$')]
    [string]$StorageAccountName,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$TenantId,

    [string]$StorageSuffix = 'file.core.windows.net',

    [switch]$ApplyConditionalAccessExclusion,

    # The app registration is created asynchronously after the ARM property flips.
    # It is usually there within seconds, but not always immediately.
    [int]$AppDiscoveryTimeoutSeconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Well-known appId of the Microsoft Graph service principal. Stable across all
# tenants in Azure Commercial; it is the resource the delegated grants target.
$script:GraphAppId = '00000003-0000-0000-c000-000000000000'

# The three delegated permissions the auto-generated storage app requests. Consent
# is granted for exactly these -- the app is autogenerated and Microsoft documents
# that editing it beyond what's described here can break it.
$script:RequiredScopes = 'openid profile User.Read'

$script:CloudGroupSidsTag = 'kdc_enable_cloud_group_sids'

# Local step logger. The orchestrator (Deploy-AvdLab.ps1) will supply the shared
# structured Write-Log described in Section 5; until it exists, this keeps the
# script runnable standalone, which is the whole point of prototyping it in
# isolation.
function Write-Step {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Blocker')][string]$Status = 'Info'
    )
    $prefix = @{ Info = '  ->'; Success = '  [ok]'; Warning = '  [!]'; Blocker = '  [BLOCKED]' }[$Status]
    $colour = @{ Info = 'Gray'; Success = 'Green'; Warning = 'Yellow'; Blocker = 'Red' }[$Status]
    Write-Host "$prefix $Message" -ForegroundColor $colour
}

function Connect-LabGraph {
    [CmdletBinding()]
    param([string]$TenantId, [bool]$NeedsConditionalAccessWrite)

    $scopes = @(
        'Application.ReadWrite.All'          # manifest tag
        'DelegatedPermissionGrant.ReadWrite.All'  # admin consent
        'Policy.Read.All'                    # security defaults + CA policy read
    )
    if ($NeedsConditionalAccessWrite) { $scopes += 'Policy.ReadWrite.ConditionalAccess' }

    $context = Get-MgContext
    if (-not $context -or $context.TenantId -ne $TenantId) {
        Write-Step "Connecting to Microsoft Graph in tenant $TenantId"
        Connect-MgGraph -TenantId $TenantId -Scopes $scopes -NoWelcome
        $context = Get-MgContext
    }

    # Fail fast on a session that authenticated but lacks a scope we need, rather
    # than half-configuring the app and erroring on step 3.
    $missing = $scopes | Where-Object { $_ -notin $context.Scopes }
    if ($missing) {
        throw "Graph session is missing required scope(s): $($missing -join ', '). Reconnect with an account holding Global Administrator."
    }
    Write-Step "Connected as $($context.Account)" -Status Success
}

function Get-StorageAccountApplication {
    [CmdletBinding()]
    param([string]$DisplayName, [int]$TimeoutSeconds)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        # -eq on displayName is an exact match; the brackets and dots in the name
        # are literal and need no escaping beyond the single quotes.
        $app = Get-MgApplication -Filter "displayName eq '$DisplayName'" -ErrorAction SilentlyContinue
        if ($app) { return $app }

        Write-Step "Waiting for Azure to create the app registration '$DisplayName'..."
        Start-Sleep -Seconds 5
    } while ((Get-Date) -lt $deadline)

    throw @"
Could not find the app registration '$DisplayName' after ${TimeoutSeconds}s.

This almost always means directoryServiceOptions is not actually 'AADKERB' on the
storage account. Confirm storage.bicep deployed, then check:
    (Get-AzStorageAccount -Name $StorageAccountName -ResourceGroupName <rg>).AzureFilesIdentityBasedAuth
"@
}

function Grant-AdminConsent {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$ClientServicePrincipalId)

    $graphSp = Get-MgServicePrincipal -Filter "appId eq '$script:GraphAppId'"

    # Select-Object -First 1: a tenant can in principle hold more than one grant for
    # the same client/resource pair. Collapsing to one keeps $existing.Id scalar.
    $existing = Get-MgOauth2PermissionGrant -Filter "clientId eq '$ClientServicePrincipalId' and consentType eq 'AllPrincipals'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ResourceId -eq $graphSp.Id } |
        Select-Object -First 1

    if ($existing) {
        # Idempotent: an existing tenant-wide grant covering our scopes is a no-op.
        $granted = $existing.Scope -split ' ' | Where-Object { $_ }
        $needed = $script:RequiredScopes -split ' '
        if (-not ($needed | Where-Object { $_ -notin $granted })) {
            Write-Step "Admin consent already granted (scopes: $($existing.Scope))" -Status Success
            return
        }

        if ($PSCmdlet.ShouldProcess($existing.Id, "Update consent scopes to '$script:RequiredScopes'")) {
            Update-MgOauth2PermissionGrant -OAuth2PermissionGrantId $existing.Id -Scope $script:RequiredScopes
            Write-Step "Updated admin consent scopes to '$script:RequiredScopes'" -Status Success
        }
        return
    }

    if ($PSCmdlet.ShouldProcess($ClientServicePrincipalId, "Grant tenant-wide admin consent for '$script:RequiredScopes'")) {
        New-MgOauth2PermissionGrant -BodyParameter @{
            clientId    = $ClientServicePrincipalId
            consentType = 'AllPrincipals'
            resourceId  = $graphSp.Id
            scope       = $script:RequiredScopes
        } | Out-Null
        Write-Step "Granted tenant-wide admin consent for '$script:RequiredScopes'" -Status Success
    }
}

function Add-CloudGroupSidsTag {
    [CmdletBinding(SupportsShouldProcess)]
    param($Application)

    # Tags is a replace-in-full collection: passing only the new tag would silently
    # drop anything Azure had already stamped on the app. Merge, never assign.
    # Filter nulls -- an app with no tags yields @($null), a 1-element array whose
    # only member would otherwise be written back as a null tag.
    $existingTags = @($Application.Tags | Where-Object { $_ })

    if ($script:CloudGroupSidsTag -in $existingTags) {
        Write-Step "Manifest tag '$script:CloudGroupSidsTag' already present" -Status Success
        return
    }

    $merged = @($existingTags + $script:CloudGroupSidsTag | Select-Object -Unique)

    if ($PSCmdlet.ShouldProcess($Application.DisplayName, "Add manifest tag '$script:CloudGroupSidsTag'")) {
        Update-MgApplication -ApplicationId $Application.Id -Tags $merged
        Write-Step "Added manifest tag '$script:CloudGroupSidsTag' (cloud-only group SIDs)" -Status Success
    }
}

function Test-MfaConfiguration {
    <#
        Returns $true when the app is clear of MFA enforcement, $false when a
        blocker remains. Never throws on a policy it merely found -- the caller
        decides what a blocker means.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$AppId, [string]$AppDisplayName, [bool]$ApplyExclusion)

    $securityDefaults = Get-MgPolicyIdentitySecurityDefaultEnforcementPolicy
    if ($securityDefaults.IsEnabled) {
        Write-Step 'Security Defaults is ENABLED in this tenant.' -Status Blocker
        Write-Host @"

    Entra Kerberos cannot work here, and no script can fix it from the inside.

    Security Defaults enforces MFA tenant-wide and exposes no per-app exclusion --
    it is on or off, with no customization. Kerberos ticket acquisition happens
    silently at logon with no UI to satisfy an MFA prompt, so the storage account
    app must be excluded from MFA, and under Security Defaults it cannot be.

    To proceed you must, deliberately and at tenant level:
      1. Disable Security Defaults (Entra admin center > Entra ID > Overview >
         Properties > Manage security defaults).
      2. Replace it with Conditional Access policies (requires Entra ID P1) that
         exclude the app '$AppDisplayName'.

    Re-run this script afterwards. It will then verify and, with
    -ApplyConditionalAccessExclusion, apply the exclusion for you.

"@ -ForegroundColor Red
        return $false
    }
    Write-Step 'Security Defaults is disabled' -Status Success

    $policies = Get-MgIdentityConditionalAccessPolicy -All -ErrorAction SilentlyContinue
    if (-not $policies) {
        Write-Step 'No Conditional Access policies found; nothing to exclude' -Status Success
        return $true
    }

    # A policy is a problem when it is on, demands MFA, targets every app, and does
    # not already exclude us. A policy scoped to specific other apps is irrelevant.
    #
    # GrantControls is null on session-only policies (sign-in frequency, persistent
    # browser), and StrictMode makes a null property walk fatal -- hence the
    # defensive hops rather than a straight $_.GrantControls.BuiltInControls.
    $blocking = $policies | Where-Object {
        $grantControls = if ($_.GrantControls) { @($_.GrantControls.BuiltInControls) } else { @() }
        $applications = if ($_.Conditions -and $_.Conditions.Applications) { $_.Conditions.Applications } else { $null }
        $included = if ($applications) { @($applications.IncludeApplications) } else { @() }
        $excluded = if ($applications) { @($applications.ExcludeApplications) } else { @() }

        $_.State -eq 'enabled' -and
        'mfa' -in $grantControls -and
        'All' -in $included -and
        $AppId -notin $excluded
    }

    if (-not $blocking) {
        Write-Step 'No enabled MFA policy targets this app' -Status Success
        return $true
    }

    foreach ($policy in $blocking) {
        if (-not $ApplyExclusion) {
            Write-Step "CA policy '$($policy.DisplayName)' requires MFA for all apps and does not exclude this app" -Status Warning
            continue
        }

        if ($PSCmdlet.ShouldProcess($policy.DisplayName, "Exclude '$AppDisplayName' from this MFA policy")) {
            $excluded = @($policy.Conditions.Applications.ExcludeApplications) + $AppId | Select-Object -Unique
            Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $policy.Id -BodyParameter @{
                conditions = @{ applications = @{ excludeApplications = $excluded } }
            }
            Write-Step "Excluded app from CA policy '$($policy.DisplayName)'" -Status Success
        }
    }

    if (-not $ApplyExclusion) {
        Write-Host @"

    $($blocking.Count) Conditional Access polic$(if ($blocking.Count -eq 1) { 'y' } else { 'ies' }) will block silent Kerberos ticket
    acquisition. FSLogix profiles will fail to load with "System error 1327".

    Re-run with -ApplyConditionalAccessExclusion to have this script exclude the
    app '$AppDisplayName' from them, or exclude it by hand in the Entra portal.

"@ -ForegroundColor Yellow
        return $false
    }

    return $true
}

# ---------------------------------------------------------------------------

$displayName = "[Storage Account] $StorageAccountName.$StorageSuffix"

Write-Host "`nConfiguring Entra Kerberos app registration for '$StorageAccountName'`n" -ForegroundColor Cyan

Connect-LabGraph -TenantId $TenantId -NeedsConditionalAccessWrite:$ApplyConditionalAccessExclusion.IsPresent

$app = Get-StorageAccountApplication -DisplayName $displayName -TimeoutSeconds $AppDiscoveryTimeoutSeconds
Write-Step "Found app registration (appId $($app.AppId))" -Status Success

$servicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'"
if (-not $servicePrincipal) {
    throw "App registration '$displayName' exists but has no service principal. Disable and re-enable Entra Kerberos on the storage account."
}

Grant-AdminConsent -ClientServicePrincipalId $servicePrincipal.Id
Add-CloudGroupSidsTag -Application $app

$mfaClear = Test-MfaConfiguration -AppId $app.AppId -AppDisplayName $displayName -ApplyExclusion $ApplyConditionalAccessExclusion.IsPresent

Write-Host ''
if (-not $mfaClear) {
    # Consent and the manifest tag are both applied and idempotent, so a re-run
    # after fixing MFA costs nothing. Exit non-zero so the orchestrator's catch
    # block fires rather than deploying session hosts onto a broken share.
    throw 'Entra Kerberos configuration is INCOMPLETE: MFA still applies to the storage account app. See the guidance above.'
}

Write-Step 'Entra Kerberos app registration is fully configured.' -Status Success
Write-Host ''
