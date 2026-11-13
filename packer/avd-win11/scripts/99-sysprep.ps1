# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), packer/avd-win11/scripts/99-sysprep.ps1; see CREDITS.md and NOTICE.
# Generalize the VM so the Compute Gallery can capture it.
$ErrorActionPreference = 'Stop'

while ((Get-Service RdAgent -ErrorAction SilentlyContinue).Status -ne 'Running') { Start-Sleep -Seconds 5 }
while ((Get-Service WindowsAzureGuestAgent -ErrorAction SilentlyContinue).Status -ne 'Running') { Start-Sleep -Seconds 5 }

$bv = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
if ($bv -and $bv.VolumeStatus -ne 'FullyDecrypted') {
    Write-Host "Disabling BitLocker on $env:SystemDrive (status: $($bv.VolumeStatus))..."
    Disable-BitLocker -MountPoint $env:SystemDrive | Out-Null
    while ((Get-BitLockerVolume -MountPoint $env:SystemDrive).VolumeStatus -ne 'FullyDecrypted') {
        Start-Sleep -Seconds 5
    }
    Write-Host "BitLocker disabled on $env:SystemDrive."
}

Remove-Item -Path "$env:SystemRoot\Panther\unattend.xml", "$env:SystemRoot\System32\Sysprep\unattend.xml" -Force -ErrorAction SilentlyContinue

$proc = Start-Process -FilePath "$env:SystemRoot\System32\Sysprep\Sysprep.exe" -ArgumentList '/oobe', '/generalize', '/quiet', '/quit' -PassThru

while ($true) {
    $state = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State').ImageState
    Write-Host $state
    if ($state -eq 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { break }
    if ($proc.HasExited) {
        $errLog = "$env:SystemRoot\System32\Sysprep\Panther\setuperr.log"
        $actLog = "$env:SystemRoot\System32\Sysprep\Panther\setupact.log"
        if (Test-Path $errLog) { Get-Content -Path $errLog -Tail 40 }
        if (Test-Path $actLog) { Get-Content -Path $actLog -Tail 40 }
        throw "Sysprep exited (code $($proc.ExitCode)) with ImageState '$state'."
    }
    Start-Sleep -Seconds 10
}
