# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), packer/avd-win11/scripts/01-base.ps1; see CREDITS.md and NOTICE.
# Changes: adds avd-landing-zone's disconnected session time limit and disables automatic Windows
# and Microsoft 365 Apps updates on golden images so hosts only change patches through image rotation.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Write-Host "Setting time zone to $env:TIMEZONE"
Set-TimeZone -Id $env:TIMEZONE

# Let session hosts redirect the time zone from the client, and end disconnected sessions so a
# forgotten session cannot hold blue/green rotation open indefinitely.
$tsPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
New-Item -Path $tsPath -Force | Out-Null
Set-ItemProperty -Path $tsPath -Name fEnableTimeZoneRedirection -Value 1 -Type DWord
$hours = if ($env:DISCONNECTED_HOURS) { [int]$env:DISCONNECTED_HOURS } else { 8 }
Set-ItemProperty -Path $tsPath -Name MaxDisconnectionTime -Value ($hours * 3600000) -Type DWord

# Disable Storage Sense; FSLogix profiles shouldn't be cleaned up by the OS.
New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense' -Force | Out-Null
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense' -Name AllowStorageSenseGlobal -Value 0 -Type DWord

# Golden image hosts get patches through a new image version and rotation, not unplanned reboots.
New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -Force | Out-Null
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -Name NoAutoUpdate -Value 1 -Type DWord

# Microsoft 365 Apps: no automatic updates in the image.
$officePath = 'HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\officeupdate'
New-Item -Path $officePath -Force | Out-Null
Set-ItemProperty -Path $officePath -Name enableautomaticupdates -Value 0 -Type DWord
Set-ItemProperty -Path $officePath -Name hideupdatenotifications -Value 1 -Type DWord
Set-ItemProperty -Path $officePath -Name hideenabledisableupdates -Value 1 -Type DWord

# FSLogix ships in the multi-session images; Configure-FSLogix configures the share per host pool.
if (-not (Test-Path 'C:\Program Files\FSLogix\Apps\frx.exe')) {
    Write-Host 'FSLogix not found, installing latest'
    $zip = "$env:TEMP\fslogix.zip"
    Invoke-WebRequest -Uri 'https://aka.ms/fslogix_download' -OutFile $zip
    Expand-Archive $zip -DestinationPath "$env:TEMP\fslogix" -Force
    Start-Process "$env:TEMP\fslogix\x64\Release\FSLogixAppsSetup.exe" -ArgumentList '/install /quiet /norestart' -Wait
}

if ($env:GPU_PRESET -eq 'True') {
    Write-Host 'Applying GPU hardware acceleration and H.264/HEVC encoding policies'
    Set-ItemProperty -Path $tsPath -Name bEnumerateHWBeforeSW -Value 1 -Type DWord
    Set-ItemProperty -Path $tsPath -Name AVC444ModePreferred -Value 1 -Type DWord
    Set-ItemProperty -Path $tsPath -Name AVCHardwareEncodePreferred -Value 1 -Type DWord
    Set-ItemProperty -Path $tsPath -Name MaxCompressionLevel -Value 1 -Type DWord
}

Write-Host 'Base configuration complete'
