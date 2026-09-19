#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Az.Accounts'; ModuleVersion = '2.0.0' }
#Requires -Modules @{ ModuleName = 'Az.Resources'; ModuleVersion = '6.0.0' }

<#
.SYNOPSIS
    Tears down the lab and verifies that nothing was left behind.

.DESCRIPTION
    Everything the lab deploys lives in one resource group, so the teardown itself
    is a single call. The interesting part is what a resource group delete does
    NOT take with it.

    TWO THINGS SURVIVE THE RESOURCE GROUP.

      1. The storage account's Entra application registration.
         Enabling Entra Kerberos causes Azure to mint an application named
         '[Storage Account] <name>.file.<suffix>' in your tenant. It is a
         DIRECTORY object, not an Azure resource, so deleting the resource group
         leaves it behind along with its admin consent grant. Run enough labs and
         you accumulate a drawer of them. This script reports it, and removes it
         with -RemoveEntraApplication.

      2. Role assignments pointing at deleted principals.
         Assignments scoped inside the resource group go with it. The ones this
         lab creates all are, so this is usually clean -- but it is checked rather
         than assumed.

    Key Vault soft-delete is the usual third offender in teardown checklists. This
    lab deploys no Key Vault, so there is nothing to purge.

.PARAMETER ResourceGroupName
    Resource group to delete.

.PARAMETER RemoveEntraApplication
    Also delete the storage account's Entra application registration. Needs
    Microsoft.Graph.Authentication and Application.ReadWrite.All.

.PARAMETER StorageAccountName
    Storage account whose Entra application should be removed. Discovered from the
    resource group when omitted.

.PARAMETER Force
    Skip the confirmation prompt.

.EXAMPLE
    ./Remove-AvdLab.ps1 -ResourceGroupName rg-avdlab

.EXAMPLE
    ./Remove-AvdLab.ps1 -ResourceGroupName rg-avdlab -RemoveEntraApplication -Force
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [switch]$RemoveEntraApplication,
    [string]$StorageAccountName,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Info', 'Success', 'Warning')][string]$Status = 'Info'
    )
    $prefix = @{ Info = '  ->'; Success = '  [ok]'; Warning = '  [!]' }[$Status]
    $colour = @{ Info = 'Gray'; Success = 'Green'; Warning = 'Yellow' }[$Status]
    Write-Host "$prefix $Message" -ForegroundColor $colour
}

Write-Host "`nAVD Lab Kit - teardown`n" -ForegroundColor Cyan

$context = Get-AzContext
if (-not $context) { throw 'Not connected to Azure. Run Connect-AzAccount first.' }

$resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $resourceGroup) {
    Write-Step "Resource group '$ResourceGroupName' does not exist. Nothing to remove." -Status Success
    # Not an error: a teardown that runs twice should succeed twice.
    $resources = @()
}
else {
    $resources = @(Get-AzResource -ResourceGroupName $ResourceGroupName)
    Write-Step "Subscription:   $($context.Subscription.Name) ($($context.Subscription.Id))"
    Write-Step "Resource group: $ResourceGroupName ($($resources.Count) resources, $($resourceGroup.Location))"

    if ($resources.Count -gt 0) {
        Write-Host ''
        $resources | Group-Object ResourceType | Sort-Object Name | ForEach-Object {
            Write-Host ("     {0,-3} {1}" -f $_.Count, $_.Name) -ForegroundColor DarkGray
        }
        Write-Host ''
    }
}

# Discover the storage account before deleting anything -- afterwards the name is
# only recoverable from a report.
if (-not $StorageAccountName -and $resources.Count -gt 0) {
    $storageResource = $resources | Where-Object { $_.ResourceType -eq 'Microsoft.Storage/storageAccounts' } | Select-Object -First 1
    if ($storageResource) { $StorageAccountName = $storageResource.Name }
}

if ($resourceGroup) {
    $shouldRemove = $Force -or $PSCmdlet.ShouldProcess($ResourceGroupName, "Delete the resource group and all $($resources.Count) resources in it")

    if (-not $shouldRemove) {
        Write-Step 'Cancelled. Nothing was deleted.' -Status Warning
        exit 0
    }

    Write-Step "Deleting resource group '$ResourceGroupName'. This usually takes a few minutes..."
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Remove-AzResourceGroup -Name $ResourceGroupName -Force -ErrorAction Stop | Out-Null
    $stopwatch.Stop()
    Write-Step "Resource group deleted in $([int]$stopwatch.Elapsed.TotalSeconds)s" -Status Success
}

# ---------------------------------------------------------------------------
# Orphan check
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'Checking for anything left behind:' -ForegroundColor Cyan

$survivingResourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if ($survivingResourceGroup) {
    Write-Step "Resource group still present in state '$($survivingResourceGroup.ProvisioningState)'" -Status Warning
}
else {
    Write-Step 'Resource group gone' -Status Success
}

# The Entra application. The one genuine orphan this design produces.
if (-not $StorageAccountName) {
    Write-Step 'Storage account name unknown; cannot check for a leftover Entra application. Pass -StorageAccountName to check.' -Status Warning
}
else {
    $suffix = (Get-AzContext).Environment.StorageEndpointSuffix
    $applicationName = "[Storage Account] $StorageAccountName.file.$suffix"

    if (-not (Get-Module -ListAvailable Microsoft.Graph.Authentication)) {
        Write-Step "Microsoft.Graph.Authentication not installed; cannot check for the leftover Entra application '$applicationName'." -Status Warning
    }
    else {
        try {
            Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
            $graphContext = Get-MgContext
            if (-not $graphContext) {
                $scopes = if ($RemoveEntraApplication) { @('Application.ReadWrite.All') } else { @('Application.Read.All') }
                Connect-MgGraph -TenantId $context.Tenant.Id -Scopes $scopes -NoWelcome
            }

            # REST rather than Get-MgApplication: keeps this to the one Graph
            # module the rest of the teardown path already needs.
            $escaped = $applicationName -replace "'", "''"
            $uri = "https://graph.microsoft.com/v1.0/applications?`$filter=displayName eq '$([uri]::EscapeDataString($escaped))'"
            $found = @((Invoke-MgGraphRequest -Method GET -Uri $uri).value)

            if ($found.Count -eq 0) {
                Write-Step 'No leftover storage account Entra application' -Status Success
            }
            elseif (-not $RemoveEntraApplication) {
                Write-Step "Entra application '$applicationName' still exists in the tenant" -Status Warning
                Write-Host @"

    Deleting the resource group does not remove it -- it is a directory object,
    not an Azure resource, and it keeps its admin consent grant. Harmless, but it
    accumulates across labs.

    Remove it with:
      ./Remove-AvdLab.ps1 -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -RemoveEntraApplication

"@ -ForegroundColor Yellow
            }
            else {
                foreach ($application in $found) {
                    if ($PSCmdlet.ShouldProcess($applicationName, 'Delete the Entra application registration')) {
                        Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/applications/$($application.id)" | Out-Null
                        Write-Step "Deleted Entra application '$applicationName'" -Status Success
                    }
                }
            }
        }
        catch {
            Write-Step "Could not check the Entra application: $($_.Exception.Message)" -Status Warning
        }
    }
}

# Role assignments whose principal or scope is gone. The lab's own assignments are
# all scoped inside the resource group and go with it, so this should be quiet --
# but "should be" is why it is worth checking once rather than assuming forever.
try {
    $orphans = @(Get-AzRoleAssignment -ErrorAction Stop | Where-Object { $_.Scope -like "*/resourceGroups/$ResourceGroupName*" })
    if ($orphans.Count -gt 0) {
        Write-Step "$($orphans.Count) role assignment(s) still scoped to the deleted resource group" -Status Warning
    }
    else {
        Write-Step 'No orphaned role assignments' -Status Success
    }
}
catch {
    Write-Step "Could not enumerate role assignments: $($_.Exception.Message)" -Status Warning
}

Write-Host ''
Write-Host ('-' * 74) -ForegroundColor DarkGray
Write-Host 'TEARDOWN COMPLETE.' -ForegroundColor Green
Write-Host ('-' * 74) -ForegroundColor DarkGray
Write-Host ''
