# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), packer/avd-win11/scripts/02-windows-update.ps1; see CREDITS.md and NOTICE.
# Install all available software updates through the Windows Update Agent API.
$ErrorActionPreference = 'Stop'

if ($env:RUN_WINDOWS_UPDATE -ne 'True') {
    Write-Host 'Skipping Windows Update'
    exit 0
}

$session  = New-Object -ComObject Microsoft.Update.Session
$searcher = $session.CreateUpdateSearcher()
Write-Host 'Searching for updates'
$result = $searcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")

if ($result.Updates.Count -eq 0) {
    Write-Host 'No updates available'
    exit 0
}

$updates = New-Object -ComObject Microsoft.Update.UpdateColl
foreach ($u in $result.Updates) {
    if (-not $u.EulaAccepted) { $u.AcceptEula() }
    Write-Host "Queued: $($u.Title)"
    [void]$updates.Add($u)
}

$downloader = $session.CreateUpdateDownloader()
$downloader.Updates = $updates
[void]$downloader.Download()

$installer = $session.CreateUpdateInstaller()
$installer.Updates = $updates
$install = $installer.Install()
Write-Host "Install result: $($install.ResultCode), reboot required: $($install.RebootRequired)"

if ($install.RebootRequired) { exit 3010 }
