#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Az.Accounts'; ModuleVersion = '2.0.0' }
#Requires -Modules @{ ModuleName = 'Az.Resources'; ModuleVersion = '6.0.0' }

<#
.SYNOPSIS
    Renders the deployment transcript as either an as-built document or an
    evidence bundle.

.DESCRIPTION
    One capture, two outputs. Both modes read the same structured transcript that
    Deploy-AvdLab.ps1 writes plus the live state of the resource group; they differ
    only in what they surface and how it is framed.

      -Mode AsBuilt   Run automatically on success. A clean Markdown and JSON
                      summary of what got deployed: names, resource IDs, the
                      connection details a user needs, the FSLogix share path, the
                      autoscale schedule, timings. The thing you keep.

      -Mode Evidence  Run automatically by the orchestrator's catch block, or by
                      hand at any time. The full transcript, the failing Bicep
                      deployment's operation detail, and the resource group's
                      actual state at the point of failure. The thing you debug
                      from.

    WHY ONE SCRIPT AND NOT TWO
    Both read the same data. Splitting them would mean two things to keep in step
    with the log format, and the log format is the single source of truth for both
    stories.

    THIS ONLY EVER LOOKS AT ITS OWN DEPLOYMENT. No tenant-wide discovery, no
    cross-subscription awareness. It answers "what did this build, and if it did
    not work, why" -- not "is this environment ready", which is a different
    question asked by a different tool.

    It is also runnable standalone against an environment deployed days ago, with
    no transcript at all -- pass just -ResourceGroupName and it reports live state.

.PARAMETER Mode
    AsBuilt or Evidence.

.PARAMETER ResourceGroupName
    Resource group to document.

.PARAMETER TranscriptPath
    Path to deployment-log.jsonl. Optional: without it the report is built from
    live Azure state alone, which is what makes after-the-fact troubleshooting work.

.PARAMETER OutputPath
    Directory to write into. Defaults to ./reports/<timestamp>.

.PARAMETER FailedStep
    Step name that failed, for Evidence mode. Set by the orchestrator.

.EXAMPLE
    ./New-AvdLabReport.ps1 -Mode Evidence -ResourceGroupName rg-avdlab

.EXAMPLE
    ./New-AvdLabReport.ps1 -Mode AsBuilt -ResourceGroupName rg-avdlab -TranscriptPath ./reports/20260919-101500/deployment-log.jsonl
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('AsBuilt', 'Evidence')]
    [string]$Mode,

    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [string]$TranscriptPath,
    [string]$OutputPath,
    [string]$FailedStep
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:GeneratedUtc = (Get-Date).ToUniversalTime()

if (-not $OutputPath) {
    $OutputPath = Join-Path (Split-Path -Parent $PSScriptRoot) "reports/$($script:GeneratedUtc.ToString('yyyyMMdd-HHmmss'))"
}
if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

function Get-Transcript {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path $Path)) { return @() }
    # JSON Lines: one self-contained record per line, so a run killed mid-write
    # still leaves every completed step readable. A single JSON array would not.
    return @(Get-Content $Path | Where-Object { $_.Trim() } | ForEach-Object {
        try { $_ | ConvertFrom-Json } catch { $null }
    } | Where-Object { $_ })
}

function Get-StepValue {
    param($Record, [string]$Name)
    if ($null -eq $Record) { return $null }
    $property = $Record.PSObject.Properties[$Name]
    return $(if ($property) { $property.Value } else { $null })
}

Write-Host "`nAVD Lab Kit - $Mode report`n" -ForegroundColor Cyan

$transcript = Get-Transcript -Path $TranscriptPath
if ($transcript.Count -gt 0) {
    Write-Host "  transcript: $($transcript.Count) records from $TranscriptPath" -ForegroundColor Gray
}
else {
    Write-Host '  no transcript supplied; reporting from live Azure state only' -ForegroundColor Gray
}

# --- Live resource inventory ---
$resources = @()
$resourceGroup = $null
try {
    $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop
    $resources = @(Get-AzResource -ResourceGroupName $ResourceGroupName | Sort-Object ResourceType, Name)
    Write-Host "  resource group: $($resources.Count) resources" -ForegroundColor Gray
}
catch {
    Write-Host "  could not read resource group '$ResourceGroupName': $($_.Exception.Message)" -ForegroundColor Yellow
}

# --- Collect module outputs from the transcript ---
$moduleOutputs = [ordered]@{}
foreach ($record in $transcript) {
    $data = Get-StepValue -Record $record -Name 'data'
    if ($null -eq $data) { continue }
    $outputs = Get-StepValue -Record $data -Name 'outputs'
    if ($null -eq $outputs) { continue }
    $moduleOutputs[$record.step] = $outputs
}

$timings = @($transcript | Where-Object { (Get-StepValue -Record $_ -Name 'durationSeconds') -ne $null -and $_.status -eq 'Success' })
$failures = @($transcript | Where-Object { $_.status -eq 'Failure' })
$warnings = @($transcript | Where-Object { $_.status -eq 'Warning' })

$totalSeconds = ($timings | Measure-Object -Property durationSeconds -Sum).Sum

# ===========================================================================
# Markdown
# ===========================================================================
$markdown = [System.Text.StringBuilder]::new()
$null = $markdown.AppendLine("# AVD Lab Kit - $(if ($Mode -eq 'AsBuilt') { 'as-built' } else { 'evidence bundle' })")
$null = $markdown.AppendLine()
$null = $markdown.AppendLine("Generated: $($script:GeneratedUtc.ToString('u'))  ")
$null = $markdown.AppendLine("Resource group: ``$ResourceGroupName``  ")
if ($resourceGroup) { $null = $markdown.AppendLine("Region: ``$($resourceGroup.Location)``  ") }
if ($totalSeconds) { $null = $markdown.AppendLine("Deployment time: $([int]$totalSeconds)s across $($timings.Count) steps  ") }
$null = $markdown.AppendLine()

if ($Mode -eq 'Evidence') {
    $null = $markdown.AppendLine('## What went wrong')
    $null = $markdown.AppendLine()
    if ($FailedStep) { $null = $markdown.AppendLine("Failed at step: **$FailedStep**") ; $null = $markdown.AppendLine() }
    if ($failures.Count -gt 0) {
        foreach ($failure in $failures) {
            $null = $markdown.AppendLine("- **$($failure.step)** - $($failure.message)")
        }
    }
    else {
        $null = $markdown.AppendLine('No failure record in the transcript. If the run was interrupted rather than failing, the last completed step is at the bottom of the timeline below.')
    }
    $null = $markdown.AppendLine()
}

# --- Connection details (as-built) ---
if ($Mode -eq 'AsBuilt') {
    $null = $markdown.AppendLine('## Connecting')
    $null = $markdown.AppendLine()
    $null = $markdown.AppendLine('| | |')
    $null = $markdown.AppendLine('| --- | --- |')
    $null = $markdown.AppendLine('| Web client | https://client.wvd.microsoft.com/arm/webclient |')
    foreach ($key in @('hostpool', 'workspace', 'appgroup', 'storage', 'scalingplan')) {
        if (-not $moduleOutputs.Contains($key)) { continue }
        foreach ($property in $moduleOutputs[$key].PSObject.Properties) {
            if ($property.Name -like '*Id' -and $property.Value -like '/subscriptions/*') { continue }
            $null = $markdown.AppendLine("| $($property.Name) | ``$($property.Value)`` |")
        }
    }
    $null = $markdown.AppendLine()
}

# --- Resources ---
$null = $markdown.AppendLine('## Resources')
$null = $markdown.AppendLine()
if ($resources.Count -gt 0) {
    $null = $markdown.AppendLine('| Type | Name | Location |')
    $null = $markdown.AppendLine('| --- | --- | --- |')
    foreach ($resource in $resources) {
        $null = $markdown.AppendLine("| ``$($resource.ResourceType)`` | $($resource.Name) | $($resource.Location) |")
    }
}
else {
    $null = $markdown.AppendLine('_No resources found._')
}
$null = $markdown.AppendLine()

# --- Timeline ---
$null = $markdown.AppendLine('## Timeline')
$null = $markdown.AppendLine()
if ($transcript.Count -gt 0) {
    $null = $markdown.AppendLine('| Time (UTC) | Step | Status | Detail |')
    $null = $markdown.AppendLine('| --- | --- | --- | --- |')
    # Evidence mode keeps everything; as-built keeps the milestones. A reader of
    # an as-built document does not want every informational line, and a reader of
    # an evidence bundle must not lose one.
    $visible = if ($Mode -eq 'Evidence') { $transcript } else { $transcript | Where-Object { $_.status -in @('Success', 'Warning', 'Failure', 'Skipped') } }
    foreach ($record in $visible) {
        $time = ([datetime]$record.timestamp).ToString('HH:mm:ss')
        $detail = ($record.message -replace '\|', '\|') -replace '\r?\n', ' '
        $duration = Get-StepValue -Record $record -Name 'durationSeconds'
        if ($duration) { $detail += " _($($duration)s)_" }
        $null = $markdown.AppendLine("| $time | $($record.step) | $($record.status) | $detail |")
    }
}
else {
    $null = $markdown.AppendLine('_No transcript available._')
}
$null = $markdown.AppendLine()

if ($warnings.Count -gt 0) {
    $null = $markdown.AppendLine('## Warnings')
    $null = $markdown.AppendLine()
    foreach ($warning in $warnings) { $null = $markdown.AppendLine("- **$($warning.step)** - $($warning.message)") }
    $null = $markdown.AppendLine()
}

# --- Evidence: failing deployment operations ---
$deploymentOperations = @()
if ($Mode -eq 'Evidence') {
    $null = $markdown.AppendLine('## Failing deployment operations')
    $null = $markdown.AppendLine()
    try {
        $deployments = @(Get-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -ErrorAction Stop |
            Where-Object { $_.DeploymentName -like 'avdlab-*' } |
            Sort-Object Timestamp -Descending | Select-Object -First 5)

        $anyFailed = $false
        foreach ($deployment in $deployments) {
            if ($deployment.ProvisioningState -eq 'Succeeded') { continue }
            $anyFailed = $true
            $null = $markdown.AppendLine("### ``$($deployment.DeploymentName)`` - $($deployment.ProvisioningState)")
            $null = $markdown.AppendLine()

            # This is the layer that actually names the resource and carries the
            # service's own error text. The deployment object itself only says
            # "Failed", which is where most troubleshooting stalls.
            $operations = @(Get-AzResourceGroupDeploymentOperation -ResourceGroupName $ResourceGroupName -DeploymentName $deployment.DeploymentName -ErrorAction SilentlyContinue |
                Where-Object { $_.ProvisioningState -eq 'Failed' })

            foreach ($operation in $operations) {
                $target = $operation.TargetResource
                $status = $operation.StatusMessage | ConvertTo-Json -Depth 8 -Compress
                $deploymentOperations += [pscustomobject]@{
                    deploymentName = $deployment.DeploymentName
                    targetResource = $target
                    statusMessage  = $operation.StatusMessage
                }
                $null = $markdown.AppendLine("- ``$target``")
                $null = $markdown.AppendLine()
                $null = $markdown.AppendLine('  ```json')
                $null = $markdown.AppendLine("  $status")
                $null = $markdown.AppendLine('  ```')
                $null = $markdown.AppendLine()
            }
            if ($operations.Count -eq 0) {
                $null = $markdown.AppendLine('_No failed operations recorded for this deployment._')
                $null = $markdown.AppendLine()
            }
        }
        if (-not $anyFailed) {
            $null = $markdown.AppendLine('_All recent Bicep deployments report Succeeded. The failure was outside ARM -- a Graph call, a role assignment, or a smoke-test check. See the timeline above._')
            $null = $markdown.AppendLine()
        }
    }
    catch {
        $null = $markdown.AppendLine("_Could not read deployment operations: $($_.Exception.Message)_")
        $null = $markdown.AppendLine()
    }
}

if ($Mode -eq 'AsBuilt') {
    $null = $markdown.AppendLine('## Tearing down')
    $null = $markdown.AppendLine()
    $null = $markdown.AppendLine('```powershell')
    $null = $markdown.AppendLine("./scripts/Remove-AvdLab.ps1 -ResourceGroupName $ResourceGroupName")
    $null = $markdown.AppendLine('```')
    $null = $markdown.AppendLine()
    $null = $markdown.AppendLine('The storage account''s Entra application registration is a directory object and is _not_ removed with the resource group. The teardown script reports it and can delete it with `-RemoveEntraApplication`.')
    $null = $markdown.AppendLine()
}

# ===========================================================================
# Write
# ===========================================================================
$stem = if ($Mode -eq 'AsBuilt') { 'as-built' } else { 'evidence' }
$markdownPath = Join-Path $OutputPath "$stem.md"
$jsonPath = Join-Path $OutputPath "$stem.json"

$markdown.ToString() | Set-Content -Path $markdownPath -Encoding utf8

[pscustomobject]@{
    mode                 = $Mode
    generatedUtc         = $script:GeneratedUtc.ToString('o')
    resourceGroupName    = $ResourceGroupName
    location             = $(if ($resourceGroup) { $resourceGroup.Location } else { $null })
    failedStep           = $FailedStep
    totalDurationSeconds = $totalSeconds
    moduleOutputs        = $moduleOutputs
    resources            = @($resources | ForEach-Object { [pscustomobject]@{ type = $_.ResourceType; name = $_.Name; id = $_.ResourceId; location = $_.Location } })
    transcript           = $transcript
    failedOperations     = $deploymentOperations
} | ConvertTo-Json -Depth 12 | Set-Content -Path $jsonPath -Encoding utf8

# Evidence bundles travel. Keeping the raw transcript beside the rendered report
# means somebody can re-render it without needing the original machine.
if ($Mode -eq 'Evidence' -and $TranscriptPath -and (Test-Path $TranscriptPath)) {
    $copyPath = Join-Path $OutputPath 'deployment-log.jsonl'
    if ((Resolve-Path $TranscriptPath).Path -ne (Join-Path (Resolve-Path $OutputPath).Path 'deployment-log.jsonl')) {
        Copy-Item $TranscriptPath $copyPath -Force
    }
}

Write-Host ''
Write-Host "  $markdownPath" -ForegroundColor Green
Write-Host "  $jsonPath" -ForegroundColor Green
Write-Host ''
