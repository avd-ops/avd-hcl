/*
  sessionhosts.bicep — the session host VMs, joined to Microsoft Entra ID and
  registered to the host pool.

  This is the module with the most moving parts, because a session host is only
  useful once four separate things have all succeeded on it:

    1. The VM exists, on the private subnet, with NO public IP.
    2. It is joined to Microsoft Entra ID          (AADLoginForWindows extension)
    3. The AVD agent is installed and registered   (DSC extension + reg. token)
    4. FSLogix and Kerberos are configured         (Custom Script Extension)

  Each is a separate VM extension, and they are chained with dependsOn so they
  run in that order. Azure will happily start two extensions at once otherwise,
  and the failure that produces — an agent installed before the machine has an
  Entra identity — looks like a registration problem rather than an ordering one.

  NO PUBLIC IP, AND NO INBOUND RULE. AVD's reverse-connect transport means the
  session host dials out to the AVD service and user sessions ride back down that
  connection. There is nothing to expose. Outbound egress comes from the NAT
  gateway in network.bicep; without it the agent cannot reach the service to
  register, and the pool comes up empty with every deployment reporting success.

  TRUSTED LAUNCH IS NOT OPTIONAL HERE. Windows 11 requires a TPM, so the VM is
  deployed with securityType 'TrustedLaunch' and vTPM enabled. Dropping it does
  not produce a clear error — it produces a VM that fails to run the OS properly.
*/

@description('Number of session hosts to deploy.')
@minValue(1)
@maxValue(50)
param sessionHostCount int = 3

@description('Name prefix for session hosts. Keep short: the Windows computer name is derived from it and has a 15-character limit.')
@maxLength(12)
param sessionHostPrefix string = 'vm-avdlab'

@description('Index of the first session host. Lets a later run add hosts 3..4 without renaming 0..2.')
@minValue(0)
param sessionHostIndexStart int = 0

@description('Azure region. Must match the host pool.')
param location string = resourceGroup().location

@description('VM size for each session host.')
param vmSize string = 'Standard_D4ads_v5'

@description('Resource ID of the subnet to attach session host NICs to. Output of network.bicep.')
param subnetId string

@description('Name of the host pool to register with.')
param hostPoolName string

@description('Host pool registration token. Obtained from hostpool.bicep via listRegistrationTokens().')
@secure()
param registrationToken string

@description('Local administrator username. Used only for provisioning; Entra ID join removes the long-term need for it.')
param adminUsername string = 'avdlabadmin'

@description('Local administrator password, generated at runtime by the orchestrator and discarded afterwards. Never hardcode, and never give this a default.')
@secure()
param adminPassword string

@description('Marketplace image publisher.')
param imagePublisher string = 'MicrosoftWindowsDesktop'

@description('Marketplace image offer.')
param imageOffer string = 'windows-11'

@description('Marketplace image SKU. Must be an -avd SKU: those are the Enterprise multi-session editions.')
param imageSku string = 'win11-25h2-avd'

@description('OS disk storage type.')
@allowed([
  'Standard_LRS'
  'StandardSSD_LRS'
  'Premium_LRS'
])
param osDiskType string = 'StandardSSD_LRS'

@description('OS disk size in GB.')
@minValue(64)
@maxValue(2048)
param osDiskSizeGb int = 128

@description('''
Configure FSLogix profile containers on each host. Set false for the documented
local-profile fallback: if Entra Kerberos will not cooperate, the rest of the lab
(host pool, load balancing, autoscale, app group) still works, and profiles simply
become local and non-roaming. A blocked dependency should not take the whole demo
down with it.
''')
param enableFsLogix bool = true

@description('UNC path to the FSLogix profile share, as output by storage.bicep (profileShareUncPath). Ignored when enableFsLogix is false.')
param profileShareUncPath string = ''

@description('''
URL of the AVD agent DSC configuration package. Microsoft publishes and versions
this; it installs the Remote Desktop Agent and Agent Boot Loader and registers the
host with the pool. Pinned as a parameter rather than hardcoded so a broken
release can be rolled back without editing the module.

The storage suffix comes from environment() rather than a literal
'blob.core.windows.net'. The lab targets Azure Commercial, so the two resolve
identically today -- but a literal host is how a template silently becomes
Commercial-only in a way nobody notices until someone forks it for another cloud.
''')
param avdAgentPackageUrl string = 'https://wvdportalstorageblob.blob.${environment().suffixes.storage}/galleryartifacts/Configuration_1.0.02990.1442.zip'

@description('Tags applied to every resource in this module.')
param tags object = {}

// ---------------------------------------------------------------------------
// Client-side configuration script, run by the Custom Script Extension.
//
// Written as a multi-line string with placeholder tokens substituted below.
// Bicep's ''' strings do not interpolate, which is exactly what we want for
// PowerShell: no escaping of $variables, no backtick gymnastics. The two values
// that do vary get swapped in with replace().
// ---------------------------------------------------------------------------
var configScriptTemplate = '''
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

function Set-RegValue {
    param($Path, $Name, $Value, $Type = 'DWord')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    Write-Output "  set $Path\$Name"
}

Write-Output '== Microsoft Entra Kerberos client configuration =='

# Lets the machine request Kerberos tickets from Entra ID rather than a domain
# controller. Without it there is no cloud KDC in the picture at all.
Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters' `
             -Name 'CloudKerberosTicketRetrievalEnabled' -Value 1

# Lets the logged-on user's credential key be loaded from their profile, which is
# what makes the ticket available for the SMB mount during logon.
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\AzureADAccount' `
             -Name 'LoadCredKeyFromProfile' -Value 1

# Two services carry this. WinHttpAutoProxySvc carries the KDC Proxy requests that
# cloud ticket retrieval depends on, and iphlpsvc is its transport. A hardening
# baseline may have disabled either, so verify rather than assume -- this fails
# silently at logon otherwise, which is the worst time to discover it.
#
# Note: disabling WPAD itself via registry is a legitimate hardening step and does
# NOT require stopping this service. The service must run; WPAD need not be used.
Write-Output '== Kerberos prerequisite services =='
foreach ($svcName in @('WinHttpAutoProxySvc', 'iphlpsvc')) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if (-not $svc) { Write-Warning "  service $svcName not found on this image"; continue }

    if ((Get-Service $svcName).StartType -eq 'Disabled') {
        Set-Service -Name $svcName -StartupType Automatic
        Write-Output "  $svcName was Disabled -> set to Automatic"
    }
    if ($svc.Status -ne 'Running') {
        Start-Service -Name $svcName
        Write-Output "  $svcName started"
    } else {
        Write-Output "  $svcName already running"
    }
}

__FSLOGIX_BLOCK__

Write-Output '== Session host configuration complete =='
'''

var fslogixBlock = '''
Write-Output '== FSLogix profile containers =='

# FSLogix ships pre-installed on the Windows Enterprise multi-session marketplace
# images, so this configures it rather than installing it. If the service is
# genuinely absent the image is not what we think it is -- say so loudly.
if (-not (Get-Service -Name 'frxsvc' -ErrorAction SilentlyContinue)) {
    Write-Warning '  FSLogix service (frxsvc) not found. Expected pre-installed on the multi-session image.'
}

$profilesKey = 'HKLM:\SOFTWARE\FSLogix\Profiles'
Set-RegValue -Path $profilesKey -Name 'Enabled' -Value 1

# VHDLocations is REG_MULTI_SZ. Writing it as a plain string is accepted by the
# registry and then ignored by FSLogix, which is a genuinely hard failure to spot.
Set-RegValue -Path $profilesKey -Name 'VHDLocations' -Value @('__VHD_LOCATION__') -Type MultiString

# Pooled hosts are shared, so a stale local profile must not win over the container.
Set-RegValue -Path $profilesKey -Name 'DeleteLocalProfileWhenVHDShouldApply' -Value 1

# username%sid rather than sid%username: sorts the share by human-readable name,
# which matters the moment you are looking for one user's container by hand.
Set-RegValue -Path $profilesKey -Name 'FlipFlopProfileDirectoryName' -Value 1

Set-RegValue -Path $profilesKey -Name 'VolumeType' -Value 'VHDX' -Type String
Write-Output '  FSLogix configured against __VHD_LOCATION__'
'''

var configScript = replace(
  replace(configScriptTemplate, '__FSLOGIX_BLOCK__', enableFsLogix ? fslogixBlock : 'Write-Output \'== FSLogix disabled; profiles will be local and non-roaming ==\''),
  '__VHD_LOCATION__',
  profileShareUncPath
)

// The CSE runs a file rather than an inline command. -EncodedCommand is the
// obvious alternative and is a trap: it expects UTF-16LE base64, while Bicep's
// base64() emits UTF-8, so the command arrives as mojibake. Writing the decoded
// bytes to a file and invoking it sidesteps the encoding mismatch entirely.
var configScriptPath = 'C:\\Windows\\Temp\\Configure-AvdLabSessionHost.ps1'
var configCommand = 'powershell -ExecutionPolicy Bypass -NoProfile -Command "[IO.File]::WriteAllBytes(\'${configScriptPath}\', [Convert]::FromBase64String(\'${base64(configScript)}\')); & \'${configScriptPath}\'"'

// ---------------------------------------------------------------------------
// Network interfaces — one per host, private only.
// ---------------------------------------------------------------------------
resource nics 'Microsoft.Network/networkInterfaces@2024-05-01' = [for i in range(0, sessionHostCount): {
  name: '${sessionHostPrefix}-${sessionHostIndexStart + i}-nic'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
          // No publicIPAddress property, deliberately. See the header.
        }
      }
    ]
  }
}]

// ---------------------------------------------------------------------------
// Session host VMs
// ---------------------------------------------------------------------------
resource sessionHosts 'Microsoft.Compute/virtualMachines@2024-07-01' = [for i in range(0, sessionHostCount): {
  name: '${sessionHostPrefix}-${sessionHostIndexStart + i}'
  location: location
  tags: tags

  // Required by the AADLoginForWindows extension: the machine needs its own
  // identity before it can be joined to a directory as itself.
  identity: {
    type: 'SystemAssigned'
  }

  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }

    storageProfile: {
      imageReference: {
        publisher: imagePublisher
        offer: imageOffer
        sku: imageSku
        version: 'latest'
      }
      osDisk: {
        name: '${sessionHostPrefix}-${sessionHostIndexStart + i}-osdisk'
        createOption: 'FromImage'
        diskSizeGB: osDiskSizeGb
        managedDisk: {
          storageAccountType: osDiskType
        }
        // Pooled session hosts are cattle: the profile lives on the FSLogix share,
        // not the OS disk, so the disk dies with the VM by design.
        deleteOption: 'Delete'
      }
    }

    osProfile: {
      computerName: '${sessionHostPrefix}-${sessionHostIndexStart + i}'
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
        patchSettings: {
          // Manual: an unattended reboot mid-demo is not a feature. A real
          // deployment would use AutomaticByPlatform with a maintenance window.
          patchMode: 'Manual'
        }
      }
    }

    networkProfile: {
      networkInterfaces: [
        {
          id: nics[i].id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }

    // Windows 11 requires a TPM. Trusted Launch supplies a virtual one.
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }

    // Managed boot diagnostics: serial console and screenshots with no storage
    // account to create, secure, or forget to delete.
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }

    licenseType: 'Windows_Client'
  }
}]

// ---------------------------------------------------------------------------
// Extension 1 — Microsoft Entra ID join
// ---------------------------------------------------------------------------
resource entraJoin 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = [for i in range(0, sessionHostCount): {
  parent: sessionHosts[i]
  name: 'AADLoginForWindows'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Azure.ActiveDirectory'
    type: 'AADLoginForWindows'
    typeHandlerVersion: '2.0'
    autoUpgradeMinorVersion: true
    // No mdmId: enrolling into Intune is a deliberate non-goal here. If the
    // tenant has MDM auto-enrollment scoped for Entra-joined devices, hosts will
    // enroll anyway -- that is a tenant setting, not something this asks for.
  }
}]

// ---------------------------------------------------------------------------
// Extension 2 — AVD agent install + host pool registration
//
// dependsOn the Entra join above: the agent registers the host as a directory
// object, so the machine needs its identity first.
// ---------------------------------------------------------------------------
resource avdAgent 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = [for i in range(0, sessionHostCount): {
  parent: sessionHosts[i]
  name: 'Microsoft.PowerShell.DSC'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Powershell'
    type: 'DSC'
    typeHandlerVersion: '2.73'
    autoUpgradeMinorVersion: true
    settings: {
      modulesUrl: avdAgentPackageUrl
      configurationFunction: 'Configuration.ps1\\AddSessionHost'
      properties: {
        hostPoolName: hostPoolName
        aadJoin: true
      }
    }
    // The registration token is a credential: it authorizes a machine to join
    // the pool. protectedSettings is encrypted at rest and, unlike settings, is
    // not returned by a GET on the extension.
    protectedSettings: {
      properties: {
        registrationInfoToken: registrationToken
      }
    }
  }
  dependsOn: [
    entraJoin[i]
  ]
}]

// ---------------------------------------------------------------------------
// Extension 3 — FSLogix + Kerberos client configuration
// ---------------------------------------------------------------------------
resource hostConfig 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = [for i in range(0, sessionHostCount): {
  parent: sessionHosts[i]
  name: 'ConfigureAvdLabSessionHost'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      // In protectedSettings rather than settings: the command line embeds the
      // whole configuration script, and settings is readable via a plain GET.
      commandToExecute: configCommand
    }
  }
  dependsOn: [
    avdAgent[i]
  ]
}]

@description('Names of the deployed session hosts.')
output sessionHostNames array = [for i in range(0, sessionHostCount): sessionHosts[i].name]

@description('Resource IDs of the deployed session hosts. Consumed by monitoring.bicep for the AMA and DCR association.')
output sessionHostIds array = [for i in range(0, sessionHostCount): sessionHosts[i].id]

@description('Number of session hosts deployed.')
output sessionHostCount int = sessionHostCount

@description('Whether FSLogix profile containers were configured on these hosts.')
output fsLogixEnabled bool = enableFsLogix
