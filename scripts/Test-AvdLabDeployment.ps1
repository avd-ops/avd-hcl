#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Az.Accounts'; ModuleVersion = '2.0.0' }
#Requires -Modules @{ ModuleName = 'Az.Resources'; ModuleVersion = '6.0.0' }
#Requires -Modules @{ ModuleName = 'Az.Storage'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Smoke-tests a deployed AVD lab and reports what is actually working.

.DESCRIPTION
    Every check here exists because the corresponding failure is SILENT. Things
    that fail loudly do not need a smoke test -- the deployment already told you.
    These are the ones where every resource reports Succeeded and the lab still
    does not work:

      * Session hosts deployed but never registered  -> no outbound path
      * Host pool with zero available hosts          -> agent or token problem
      * Storage account without AADKERB              -> profiles cannot mount
      * Missing share RBAC                           -> profiles fail to load
      * Missing autoscale RBAC                       -> plan never runs
      * Workspace publishing nothing                 -> users see an empty feed
      * A public IP on a session host                -> the design has drifted

    Read-only throughout. It changes nothing and is safe to run against a live
    environment as often as you like.

.PARAMETER ResourceGroupName
    Resource group holding the lab.

.PARAMETER HostPoolName
    Host pool to check.

.PARAMETER StorageAccountName
    FSLogix storage account. Omit if deployed with -SkipFSLogix.

.PARAMETER ExpectedHostCount
    How many session hosts should be registered and available.

.PARAMETER OutputPath
    Optional. Writes the results as JSON alongside the console output.

.EXAMPLE
    ./Test-AvdLabDeployment.ps1 -ResourceGroupName rg-avdlab -HostPoolName hp-avdlab-pooled `
        -StorageAccountName stavdlabfslogix -ExpectedHostCount 3
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$HostPoolName,

    [string]$StorageAccountName,

    [int]$ExpectedHostCount = 3,

    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AvdApiVersion = '2024-04-03'
$script:Results = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param(
        [Parameter(Mandatory)][string]$Check,
        [Parameter(Mandatory)][ValidateSet('Pass', 'Fail', 'Warn', 'Skipped')][string]$Status,
        [Parameter(Mandatory)][string]$Detail,
        [string]$Action = ''
    )
    $script:Results.Add([pscustomobject]@{ Check = $Check; Status = $Status; Detail = $Detail; Action = $Action })

    $glyph, $colour = switch ($Status) {
        'Pass' { '[ok]', 'Green' }
        'Fail' { '[FAIL]', 'Red' }
        'Warn' { '[warn]', 'Yellow' }
        'Skipped' { '[skip]', 'DarkGray' }
    }
    Write-Host ('  {0,-8} {1,-34} {2}' -f $glyph, $Check, $Detail) -ForegroundColor $colour
    if ($Action) { Write-Host ('           -> {0}' -f $Action) -ForegroundColor $colour }
}

function Invoke-AvdRest {
    param([Parameter(Mandatory)][string]$Path)
    $response = Invoke-AzRestMethod -Method GET -Path $Path
    if ($response.StatusCode -ge 400) {
        throw "GET $Path returned $($response.StatusCode): $($response.Content)"
    }
    return $response.Content | ConvertFrom-Json
}

# ---------------------------------------------------------------------------

Write-Host "`nAVD Lab Kit - deployment smoke test`n" -ForegroundColor Cyan

$context = Get-AzContext
if (-not $context) { throw 'Not connected to Azure. Run Connect-AzAccount first.' }
$subscriptionId = $context.Subscription.Id
$rgScope = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName"

# --- Resource group ---
$resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $resourceGroup) {
    Add-Check -Check 'Resource group' -Status Fail -Detail "$ResourceGroupName not found"
    exit 1
}
Add-Check -Check 'Resource group' -Status Pass -Detail "$ResourceGroupName in $($resourceGroup.Location)"

# --- Host pool and session host registration ---
# The headline check. A host pool with zero available hosts is the exact failure
# an empty outbound path produces, and nothing else in the deployment complains.
try {
    $hostPoolPath = "$rgScope/providers/Microsoft.DesktopVirtualization/hostPools/$HostPoolName"
    $hostPool = Invoke-AvdRest -Path "$hostPoolPath`?api-version=$script:AvdApiVersion"
    Add-Check -Check 'Host pool' -Status Pass -Detail "$HostPoolName ($($hostPool.properties.hostPoolType), $($hostPool.properties.loadBalancerType))"

    $sessionHosts = @((Invoke-AvdRest -Path "$hostPoolPath/sessionHosts`?api-version=$script:AvdApiVersion").value)
    $available = @($sessionHosts | Where-Object { $_.properties.status -eq 'Available' })

    if ($sessionHosts.Count -eq 0) {
        Add-Check -Check 'Session host registration' -Status Fail -Detail "0 of $ExpectedHostCount registered" `
            -Action 'The VMs deployed but no agent reached the service. Check the NAT gateway and that the registration token had not expired.'
    }
    elseif ($available.Count -lt $ExpectedHostCount) {
        $statuses = ($sessionHosts | ForEach-Object { "$(($_.name -split '/')[-1])=$($_.properties.status)" }) -join ', '
        Add-Check -Check 'Session host registration' -Status Warn -Detail "$($available.Count) of $ExpectedHostCount available ($statuses)" `
            -Action 'Hosts can take a few minutes to report Available after the agent installs.'
    }
    else {
        Add-Check -Check 'Session host registration' -Status Pass -Detail "$($available.Count) of $ExpectedHostCount available"
    }

    foreach ($sessionHost in $sessionHosts) {
        $name = ($sessionHost.name -split '/')[-1]
        if ($sessionHost.properties.updateState -eq 'Failed' -or $sessionHost.properties.status -eq 'Unavailable') {
            Add-Check -Check "  host $name" -Status Warn -Detail "status=$($sessionHost.properties.status) $($sessionHost.properties.statusTimestamp)"
        }
    }
}
catch {
    Add-Check -Check 'Host pool' -Status Fail -Detail $_.Exception.Message
}

# --- Workspace publishing ---
try {
    $workspaces = @((Invoke-AvdRest -Path "$rgScope/providers/Microsoft.DesktopVirtualization/workspaces`?api-version=$script:AvdApiVersion").value)
    foreach ($workspace in $workspaces) {
        $references = @($workspace.properties.applicationGroupReferences)
        if ($references.Count -eq 0) {
            Add-Check -Check 'Workspace publishing' -Status Fail -Detail "$($workspace.name) publishes nothing" `
                -Action 'Users will subscribe successfully and see an empty feed. Re-deploy workspace.bicep with the application group ID.'
        }
        else {
            Add-Check -Check 'Workspace publishing' -Status Pass -Detail "$($workspace.name) publishes $($references.Count) application group(s)"
        }
    }
    if ($workspaces.Count -eq 0) { Add-Check -Check 'Workspace publishing' -Status Fail -Detail 'no workspace found' }
}
catch {
    Add-Check -Check 'Workspace publishing' -Status Fail -Detail $_.Exception.Message
}

# --- No public IP on any session host ---
# Not paranoia: if this ever fails, someone has changed the network design and
# very likely does not realise AVD never needed inbound access in the first place.
try {
    $publicIps = @(Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.Network/publicIPAddresses')
    $nonNatIps = @($publicIps | Where-Object { $_.Name -notlike '*natgw*' })
    if ($nonNatIps.Count -gt 0) {
        Add-Check -Check 'No public IP on hosts' -Status Fail -Detail "unexpected public IP(s): $(($nonNatIps.Name) -join ', ')" `
            -Action 'AVD uses reverse connect. A session host should never have a public IP.'
    }
    else {
        Add-Check -Check 'No public IP on hosts' -Status Pass -Detail "$($publicIps.Count) public IP (NAT gateway only, outbound)"
    }

    $natGateways = @(Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.Network/natGateways')
    if ($natGateways.Count -eq 0) {
        Add-Check -Check 'Outbound egress path' -Status Fail -Detail 'no NAT gateway' `
            -Action 'Without explicit egress the AVD agent cannot register. Default outbound access was retired in March 2026.'
    }
    else {
        Add-Check -Check 'Outbound egress path' -Status Pass -Detail "NAT gateway $($natGateways[0].Name)"
    }
}
catch {
    Add-Check -Check 'Network shape' -Status Warn -Detail $_.Exception.Message
}

# --- FSLogix storage ---
if (-not $StorageAccountName) {
    Add-Check -Check 'FSLogix storage' -Status Skipped -Detail 'no storage account given (deployed with -SkipFSLogix?)'
}
else {
    try {
        $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction Stop
        $directoryOption = $storageAccount.AzureFilesIdentityBasedAuth.DirectoryServiceOptions

        if ($directoryOption -eq 'AADKERB') {
            Add-Check -Check 'Entra Kerberos on storage' -Status Pass -Detail "directoryServiceOptions = AADKERB"
        }
        else {
            Add-Check -Check 'Entra Kerberos on storage' -Status Fail -Detail "directoryServiceOptions = '$directoryOption'" `
                -Action 'Profiles cannot mount. Re-deploy storage.bicep.'
        }

        $shares = @(Get-AzRmStorageShare -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -ErrorAction Stop)
        if ($shares.Count -gt 0) {
            Add-Check -Check 'FSLogix share' -Status Pass -Detail "$(($shares.Name) -join ', ')"
        }
        else {
            Add-Check -Check 'FSLogix share' -Status Fail -Detail 'no file share found'
        }

        # RBAC is the whole permission model for cloud-only identities. There are
        # no NTFS ACLs to fall back on.
        $storageScope = "$rgScope/providers/Microsoft.Storage/storageAccounts/$StorageAccountName"
        $shareRoles = @(Get-AzRoleAssignment -Scope $storageScope -RoleDefinitionName 'Storage File Data SMB Share Contributor' -ErrorAction SilentlyContinue |
            Where-Object { $_.Scope -eq $storageScope })
        if ($shareRoles.Count -gt 0) {
            Add-Check -Check 'Share RBAC' -Status Pass -Detail "$($shareRoles.Count) principal(s) hold SMB Share Contributor"
        }
        else {
            Add-Check -Check 'Share RBAC' -Status Fail -Detail 'nobody holds Storage File Data SMB Share Contributor' `
                -Action 'For cloud-only identities this IS the permission model. Profiles will fail to load. Run Add-AvdLabAssignments.ps1.'
        }
    }
    catch {
        Add-Check -Check 'FSLogix storage' -Status Fail -Detail $_.Exception.Message
    }
}

# --- Autoscale ---
try {
    $scalingPlans = @((Invoke-AvdRest -Path "$rgScope/providers/Microsoft.DesktopVirtualization/scalingPlans`?api-version=$script:AvdApiVersion").value)
    if ($scalingPlans.Count -eq 0) {
        Add-Check -Check 'Scaling plan' -Status Warn -Detail 'none deployed'
    }
    else {
        $plan = $scalingPlans[0]
        $enabled = @($plan.properties.hostPoolReferences | Where-Object { $_.scalingPlanEnabled })
        Add-Check -Check 'Scaling plan' -Status Pass -Detail "$($plan.name), enabled on $($enabled.Count) host pool(s), $($plan.properties.timeZone)"

        # The silent one. The plan is healthy; it simply has no authority to act.
        $powerRoles = @(Get-AzRoleAssignment -Scope $rgScope -RoleDefinitionName 'Desktop Virtualization Power On Off Contributor' -ErrorAction SilentlyContinue)
        if ($powerRoles.Count -gt 0) {
            Add-Check -Check 'Autoscale RBAC' -Status Pass -Detail 'AVD service holds Power On Off Contributor'
        }
        else {
            Add-Check -Check 'Autoscale RBAC' -Status Fail -Detail 'Power On Off Contributor not assigned' `
                -Action 'The plan will report healthy and never start or stop a host. Run Add-AvdLabAssignments.ps1.'
        }
    }
}
catch {
    Add-Check -Check 'Scaling plan' -Status Warn -Detail $_.Exception.Message
}

# --- Monitoring ---
try {
    $workspacesLa = @(Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.OperationalInsights/workspaces')
    if ($workspacesLa.Count -gt 0) {
        Add-Check -Check 'Log Analytics' -Status Pass -Detail $workspacesLa[0].Name
    }
    else {
        Add-Check -Check 'Log Analytics' -Status Warn -Detail 'no workspace found'
    }

    $dcrs = @(Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.Insights/dataCollectionRules')
    if ($dcrs.Count -gt 0) {
        Add-Check -Check 'Data collection rule' -Status Pass -Detail $dcrs[0].Name
    }
    else {
        Add-Check -Check 'Data collection rule' -Status Warn -Detail 'none found; AVD Insights host panels will be empty'
    }
}
catch {
    Add-Check -Check 'Monitoring' -Status Warn -Detail $_.Exception.Message
}

# ---------------------------------------------------------------------------
$failures = @($script:Results | Where-Object { $_.Status -eq 'Fail' })
$warnings = @($script:Results | Where-Object { $_.Status -eq 'Warn' })

Write-Host "`n$('-' * 74)" -ForegroundColor DarkGray
if ($failures.Count -gt 0) {
    Write-Host "$($failures.Count) check(s) FAILED, $($warnings.Count) warning(s)." -ForegroundColor Red
}
elseif ($warnings.Count -gt 0) {
    Write-Host "All checks passed with $($warnings.Count) warning(s)." -ForegroundColor Yellow
}
else {
    Write-Host 'All checks passed.' -ForegroundColor Green
}
Write-Host "$('-' * 74)`n" -ForegroundColor DarkGray

if ($OutputPath) {
    $directory = Split-Path -Parent $OutputPath
    if ($directory -and -not (Test-Path $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    [pscustomobject]@{
        generatedUtc      = (Get-Date).ToUniversalTime().ToString('o')
        resourceGroupName = $ResourceGroupName
        hostPoolName      = $HostPoolName
        results           = $script:Results
    } | ConvertTo-Json -Depth 6 | Set-Content -Path $OutputPath -Encoding utf8
    Write-Host "Results written to $OutputPath`n" -ForegroundColor Gray
}

if ($failures.Count -gt 0) { exit 1 }
