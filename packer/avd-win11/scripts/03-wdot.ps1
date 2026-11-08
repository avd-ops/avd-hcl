# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), packer/avd-win11/scripts/03-wdot.ps1; see CREDITS.md and NOTICE.
# Adapted from avd-landing-zone (MIT, commit 91c7acf), scripts/image/Invoke-Wdot.ps1 (event-log pre-creation and LastRunTime check).
# Apply the Windows Desktop Optimization Tool (WDOT) with the profile rendered from wdot.pkr.hcl.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# Windows PowerShell 5.1 otherwise serializes some arrays as {"value": [...], "Count": n}.
Remove-TypeData -TypeName System.Array -ErrorAction SilentlyContinue

$settingsPath = 'C:\Windows\Temp\wdot-settings.json'
$zip = 'C:\Windows\Temp\wdot.zip'
$settings = Get-Content -Raw -Path $settingsPath | ConvertFrom-Json

if (-not $settings.enabled) {
    Write-Host 'Skipping WDOT (wdot_profile = none)'
    Remove-Item $settingsPath, $zip -Force -ErrorAction SilentlyContinue
    exit 0
}

$root = 'C:\Windows\Temp\wdot'
Expand-Archive -Path $zip -DestinationPath $root -Force
$wdot = Join-Path $root 'wdot'
$profileDir = Join-Path $wdot "Configurations\$($settings.profile_name)"
Copy-Item -Path (Join-Path $wdot 'Configurations\Templates') -Destination $profileDir -Recurse

# Every object in a config file that carries an OptimizationState, including nested ones
# (LanManWorkstation keeps its settings under Keys).
function Get-Optimization($node) {
    foreach ($n in @($node)) {
        if ($null -eq $n -or $n -isnot [psobject]) { continue }
        if ($n.PSObject.Properties['OptimizationState']) { $n }
        foreach ($p in $n.PSObject.Properties) {
            if ($p.Value -is [array]) { Get-Optimization $p.Value }
        }
    }
}

# The name an override refers to: the item's identifying field, or the last part of a key path.
function Get-OptimizationName($item) {
    foreach ($p in 'AppxPackage', 'ScheduledTask', 'Name', 'RegItemValueName') {
        if ($item.PSObject.Properties[$p]) { return $item.$p }
    }
    if ($item.PSObject.Properties['KeyName']) { return ($item.KeyName.TrimEnd('\') -split '\\')[-1] }
}

function Get-ConfigFile($name) {
    $file = Get-ChildItem -Path $profileDir -File | Where-Object { $_.BaseName -eq $name } | Select-Object -First 1
    if (-not $file) { throw "WDOT config file '$name' not found in $profileDir" }
    $file
}

function Set-ConfigFile($name, [scriptblock]$change) {
    $file = Get-ConfigFile $name
    # Every WDOT config file is a JSON array; keep it one even when it holds a single entry.
    $data = @(ConvertFrom-Json -InputObject (Get-Content -Raw -Path $file.FullName))
    $items = @(Get-Optimization $data)
    & $change $items
    ConvertTo-Json -InputObject $data -Depth 10 | Set-Content -Path $file.FullName -Encoding UTF8
}

foreach ($name in @($settings.apply_all)) {
    Set-ConfigFile $name {
        param($items)
        $n = 0
        foreach ($i in $items) { if ($i.OptimizationState -eq 'Skip') { $i.OptimizationState = 'Apply'; $n++ } }
        Write-Host "${name}: $n settings set to Apply"
    }
}

foreach ($file in @($settings.overrides.PSObject.Properties)) {
    $name = $file.Name
    $wanted = $file.Value
    Set-ConfigFile $name {
        param($items)
        $all = $wanted.PSObject.Properties['*']
        if ($all) {
            foreach ($i in $items) { if ($i.OptimizationState -in 'Apply', 'Skip') { $i.OptimizationState = $all.Value } }
            Write-Host "${name}: every setting set to $($all.Value)"
        }
        foreach ($o in $wanted.PSObject.Properties | Where-Object Name -ne '*') {
            $match = @($items | Where-Object { (Get-OptimizationName $_) -eq $o.Name })
            if ($match.Count -eq 0) { throw "WDOT override ${name}/$($o.Name) matches no setting in WDOT's $name config" }
            foreach ($i in $match) { $i.OptimizationState = $o.Value }
            Write-Host "${name}/$($o.Name): $($o.Value)"
        }
    }
}

# Pre-create the WDOT event log and its sources so a fresh VM never misses events (avd-landing-zone lesson 0031).
$sources = @('WDOT', 'EventLog', 'AppxPackages', 'Autologgers', 'DefaultUserSettings', 'DiskCleanup', 'Edge', 'LocalPolicy', 'NetworkOptimizations', 'RemoveLegacyIE', 'RemoveOneDrive', 'ScheduledTasks', 'Services', 'WindowsMediaPlayer')
$missingSources = @($sources | Where-Object { -not [System.Diagnostics.EventLog]::SourceExists($_) })
if ($missingSources.Count) { New-EventLog -LogName 'WDOT' -Source $missingSources }
Limit-EventLog -LogName 'WDOT' -OverflowAction OverWriteAsNeeded -MaximumSize 4MB

$stampKey = 'HKLM:\SOFTWARE\WDOT'
if (Test-Path $stampKey) { Remove-ItemProperty -Path $stampKey -Name 'LastRunTime' -ErrorAction SilentlyContinue }

$params = @{ ConfigProfile = $settings.profile_name; AcceptEULA = $true; Verbose = $true }
if (@($settings.optimizations).Count) { $params.Optimizations = [string[]]$settings.optimizations }
if (@($settings.advanced_optimizations).Count) { $params.AdvancedOptimizations = [string[]]$settings.advanced_optimizations }
Write-Host "Running WDOT: optimizations [$($params.Optimizations -join ', ')], advanced [$($params.AdvancedOptimizations -join ', ')]"

# WDOT warns and carries on when a single setting fails, so don't let one turn into a stop.
$ErrorActionPreference = 'Continue'
$started = (Get-Date).AddSeconds(-5)
& (Join-Path $wdot 'Windows_Optimization.ps1') @params
$ErrorActionPreference = 'Stop'

# WDOT returns without an exit code when its profile or parameters are wrong; check both its registry stamp and event log.
$stamp = Get-ItemProperty -Path $stampKey -ErrorAction SilentlyContinue
if (-not $stamp -or -not $stamp.PSObject.Properties['LastRunTime'] -or -not $stamp.LastRunTime) {
    throw 'WDOT left no LastRunTime under HKLM:\SOFTWARE\WDOT: it never started'
}
$events = @(Get-WinEvent -FilterHashtable @{ LogName = 'WDOT'; StartTime = $started } -ErrorAction SilentlyContinue)
$errors = @($events | Where-Object Level -eq 2)
$errors | ForEach-Object { Write-Warning "WDOT event $($_.Id): $($_.Message)" }
if (-not ($events | Where-Object { $_.Message -like 'WDOT Total Run Time*' })) {
    throw 'WDOT did not finish; see the warnings above'
}
Write-Host "WDOT finished with $($errors.Count) error events"

Set-Location $env:SystemRoot
Remove-Item $root, $zip, $settingsPath -Recurse -Force
