# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), packer/avd-win11/scripts/99-sysprep.ps1; see CREDITS.md and NOTICE.
# Generalize the VM so the Compute Gallery can capture it.
$ErrorActionPreference = 'Stop'

while ((Get-Service RdAgent -ErrorAction SilentlyContinue).Status -ne 'Running') { Start-Sleep -Seconds 5 }
while ((Get-Service WindowsAzureGuestAgent -ErrorAction SilentlyContinue).Status -ne 'Running') { Start-Sleep -Seconds 5 }

Remove-Item -Path "$env:SystemRoot\Panther\unattend.xml" -Force -ErrorAction SilentlyContinue

& "$env:SystemRoot\System32\Sysprep\Sysprep.exe" /oobe /generalize /quiet /quit /mode:vm

while ($true) {
    $state = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State').ImageState
    Write-Host $state
    if ($state -eq 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { break }
    Start-Sleep -Seconds 10
}
