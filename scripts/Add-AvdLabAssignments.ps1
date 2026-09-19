#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Az.Accounts'; ModuleVersion = '2.0.0' }
#Requires -Modules @{ ModuleName = 'Az.Resources'; ModuleVersion = '6.0.0' }

<#
.SYNOPSIS
    Grants the three role assignments the lab needs to actually work.

.DESCRIPTION
    Everything here is Azure RBAC, and all three are easy to forget because none
    of them fails at deployment time -- each one fails later, quietly, in a way
    that looks like something else.

      1. Desktop Virtualization User, on the application group, to the demo group.
         Without it the deployment is perfect and users see an empty feed. This is
         the one people notice first, because nothing works at all.

      2. Storage File Data SMB Share Contributor, on the storage account, to the
         demo group.
         For cloud-only identities there are NO NTFS ACLs anywhere in the picture.
         Share access is governed entirely by Azure RBAC. Every Entra Kerberos step
         can be correct and profiles will still fail to load without this.

      3. Desktop Virtualization Power On Off Contributor, on the resource group, to
         the Azure Virtual Desktop service principal.
         The scaling plan starts and stops VMs on your behalf, so the service needs
         rights to do it. Without this the plan deploys, attaches, reports healthy,
         and never powers anything on or off.

    WHY THIS IS A SCRIPT AND NOT BICEP
    Assignment 1 and 2 are keyed on the demo group's object ID, which lives in
    orchestrator.config.json -- putting them in Bicep would drag a real directory
    object ID into the tracked parameter file, which is exactly what the
    placeholders-only rule exists to prevent. Assignment 3 could live in Bicep, but
    splitting "who may access what" across a module and a script is worse than
    keeping all three together.

.PARAMETER ResourceGroupName
    Resource group holding the lab.

.PARAMETER AppGroupName
    Desktop application group to publish to the demo group.

.PARAMETER StorageAccountName
    FSLogix storage account.

.PARAMETER DemoGroupObjectId
    Object ID of the Entra security group whose members will use the lab.

.PARAMETER SkipScalingPlanRole
    Skip assignment 3. Only useful if no scaling plan is deployed.

.EXAMPLE
    ./Add-AvdLabAssignments.ps1 -ResourceGroupName rg-avdlab -AppGroupName dag-avdlab `
        -StorageAccountName stavdlabfslogix -DemoGroupObjectId <guid>
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$AppGroupName,

    [Parameter(Mandatory)]
    [string]$StorageAccountName,

    [Parameter(Mandatory)]
    [string]$DemoGroupObjectId,

    [switch]$SkipScalingPlanRole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Well-known appId of the Azure Virtual Desktop service principal. Stable across
# every tenant; the object ID behind it is per-tenant and looked up at runtime.
$script:AvdServicePrincipalAppId = '9cdead84-a844-4324-93f2-b2e6bb768d07'

function Write-Step {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Info', 'Success', 'Warning')][string]$Status = 'Info'
    )
    $prefix = @{ Info = '  ->'; Success = '  [ok]'; Warning = '  [!]' }[$Status]
    $colour = @{ Info = 'Gray'; Success = 'Green'; Warning = 'Yellow' }[$Status]
    Write-Host "$prefix $Message" -ForegroundColor $colour
}

function Add-LabRoleAssignment {
    <#
        Idempotent by inspection. New-AzRoleAssignment throws a Conflict when the
        assignment already exists, and catching that is indistinguishable from
        catching a real failure -- so check first and treat "already there" as the
        success it is.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$ObjectId,
        [Parameter(Mandatory)][string]$RoleDefinitionName,
        [Parameter(Mandatory)][string]$Scope,
        [Parameter(Mandatory)][string]$Description
    )

    $existing = Get-AzRoleAssignment -ObjectId $ObjectId -Scope $Scope -RoleDefinitionName $RoleDefinitionName -ErrorAction SilentlyContinue |
        Where-Object { $_.Scope -eq $Scope }

    if ($existing) {
        Write-Step "$Description - already assigned" -Status Success
        return
    }

    if (-not $PSCmdlet.ShouldProcess($Scope, "Assign '$RoleDefinitionName' to $ObjectId")) {
        Write-Step "$Description - would assign (WhatIf)" -Status Info
        return
    }

    try {
        New-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleDefinitionName -Scope $Scope -ErrorAction Stop | Out-Null
        Write-Step "$Description - assigned" -Status Success
    }
    catch {
        if ($_.Exception.Message -match 'already exists|RoleAssignmentExists') {
            # A race against another run, or a propagation delay on the read above.
            Write-Step "$Description - already assigned" -Status Success
            return
        }
        if ($_.Exception.Message -match 'AuthorizationFailed|does not have authorization') {
            throw @"
Not authorized to create a role assignment at:
    $Scope

Granting a role requires the authority to grant roles. You need Owner, or
Contributor plus User Access Administrator, on the subscription. Being a Global
Administrator in the tenant grants nothing in Azure -- they are separate systems.
"@
        }
        throw
    }
}

# ---------------------------------------------------------------------------

Write-Host "`nAVD Lab Kit - access assignments`n" -ForegroundColor Cyan

if ($DemoGroupObjectId -like '<*>') {
    throw @"
DemoGroupObjectId is still a placeholder ('$DemoGroupObjectId').

Create an Entra security group for your lab users and put its object ID in
orchestrator.local.config.json as assignment.demoGroupObjectId. The tracked
orchestrator.config.json keeps the placeholder.
"@
}

$context = Get-AzContext
if (-not $context) { throw 'Not connected to Azure. Run Connect-AzAccount first.' }
$subscriptionId = $context.Subscription.Id

# Confirm the group exists before granting it anything. A typo'd object ID
# produces a role assignment to a principal that is not there, which succeeds and
# then explains nothing when users cannot sign in.
try {
    $group = Get-AzADGroup -ObjectId $DemoGroupObjectId -ErrorAction Stop
    Write-Step "Demo group: $($group.DisplayName) ($DemoGroupObjectId)" -Status Success
}
catch {
    throw "Could not find an Entra group with object ID '$DemoGroupObjectId' in tenant $($context.Tenant.Id): $($_.Exception.Message)"
}

# ---- 1. Desktop access ----
$appGroupScope = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.DesktopVirtualization/applicationGroups/$AppGroupName"
Add-LabRoleAssignment -ObjectId $DemoGroupObjectId `
    -RoleDefinitionName 'Desktop Virtualization User' `
    -Scope $appGroupScope `
    -Description 'Desktop Virtualization User on the application group'

# ---- 2. FSLogix share access ----
$storageScope = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/$StorageAccountName"
Add-LabRoleAssignment -ObjectId $DemoGroupObjectId `
    -RoleDefinitionName 'Storage File Data SMB Share Contributor' `
    -Scope $storageScope `
    -Description 'Storage File Data SMB Share Contributor on the FSLogix storage account'

# ---- 3. Autoscale power management ----
if ($SkipScalingPlanRole) {
    Write-Step 'Skipping the AVD power-management role (-SkipScalingPlanRole). Autoscale will not start or stop hosts.' -Status Warning
}
else {
    $avdSp = Get-AzADServicePrincipal -ApplicationId $script:AvdServicePrincipalAppId -ErrorAction SilentlyContinue
    if (-not $avdSp) {
        Write-Step "Azure Virtual Desktop service principal not found in this tenant (appId $script:AvdServicePrincipalAppId)." -Status Warning
        Write-Host @'
    The scaling plan will deploy and do nothing. The service principal normally
    appears once Microsoft.DesktopVirtualization is registered; if it is missing,
    re-register the provider and run this script again.
'@ -ForegroundColor Yellow
    }
    else {
        $resourceGroupScope = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName"
        Add-LabRoleAssignment -ObjectId $avdSp.Id `
            -RoleDefinitionName 'Desktop Virtualization Power On Off Contributor' `
            -Scope $resourceGroupScope `
            -Description 'Desktop Virtualization Power On Off Contributor for the AVD service (autoscale)'
    }
}

Write-Host ''
Write-Step 'Access assignments complete.' -Status Success
Write-Host ''
Write-Host '  Role assignments can take a few minutes to propagate. A user who cannot' -ForegroundColor DarkGray
Write-Host '  see the desktop immediately after this is usually waiting on that, not broken.' -ForegroundColor DarkGray
Write-Host ''
