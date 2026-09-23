/*
  storage.bicep — Azure Files share for FSLogix profile containers.

  This module carries the single most important line in the whole lab:

      directoryServiceOptions: 'AADKERB'

  That enables Microsoft Entra Kerberos on the storage account, which is what
  lets Entra ID-joined session hosts — with no domain controller and no line of
  sight to one — mount an SMB share and load FSLogix profiles. Entra ID issues
  the Kerberos tickets directly.

  It is a declarative ARM property, so a re-run converges instead of drifting.
  (An earlier revision of the spec assumed this had to be done imperatively with
  `Set-AzStorageAccount -EnableAzureActiveDirectoryKerberosForFile`. That cmdlet
  still works and remains the fallback, but it is no longer the only path.)

  WHAT THIS MODULE CANNOT DO
  Enabling the toggle causes Azure to mint an Entra app registration for the
  storage account. Three things must then be done *to that app registration*,
  and none of them are ARM resources — they are Microsoft Graph calls needing
  Global Admin. `Set-AvdLabFSLogixAuth.ps1` runs immediately after this module:

    1. Grant admin consent to the new service principal.
    2. Exclude that principal from MFA. Kerberos tickets are acquired silently
       during logon; there is no UI to answer an MFA prompt. If the tenant has
       Security Defaults on, this is mandatory, not optional.
    3. Add the `kdc_enable_cloud_group_sids` manifest tag. MANDATORY for
       cloud-only identities, which is exactly what Easy Mode uses. Without it
       Entra omits cloud-only group SIDs from the ticket, and share permissions
       granted to an Entra group silently fail to resolve.

  Deploying this module alone gets you a share that looks perfectly configured
  and does not work.
*/

@description('Azure region for the storage account.')
param location string = resourceGroup().location

@description('''
Short name identifying this lab. Every resource name in every module derives
from it, which is what lets several labs coexist in one subscription and what
lets the management commands find a lab knowing nothing but its name.

3-9 characters, lowercase letters and digits.

The 9-character ceiling is arithmetic, not taste. Windows computer names are
limited to 15 characters, session hosts are named vm-<labName>-<n>, and
sessionHostCount allows a two-digit index:

    'vm-' (3) + labName (9) + '-' (1) + '49' (2) = 15

A longer lab name produces a computer name ARM rejects, and it rejects it at
the session host phase -- after the network, storage and host pool are already
built.
''')
@minLength(3)
@maxLength(9)
param labName string = 'lab'

@description('Name of the file share holding FSLogix profile containers.')
param shareName string = 'profiles'

@description('Share quota in GiB. Standard shares bill on used capacity, not quota, so this is a ceiling rather than a cost.')
@minValue(100)
@maxValue(102400)
param shareQuotaGb int = 1024

@description('Storage redundancy. Standard_LRS is right for a short-lived lab. FSLogix at production scale usually wants Premium (FileStorage / Premium_LRS) for the lower latency on profile load.')
@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param storageSkuName string = 'Standard_LRS'

@description('Tags applied to every resource in this module.')
param tags object = {}

var labTags = union(tags, { 'avdlab-name': labName })

var isPremium = startsWith(storageSkuName, 'Premium')

// ---------------------------------------------------------------------------
// The storage account name is DERIVED, not supplied.
//
// Storage account names are globally unique across all of Azure, 3-24
// characters, lowercase alphanumeric with no hyphens. A predictable name like
// 'stavdlab${labName}' would collide with every other person who forked this
// repo and picked the same lab name -- and they would find out at deployment
// time, with an error that names the constraint but not the cause.
//
// uniqueString(resourceGroup().id) is deterministic: the same lab in the same
// resource group always resolves to the same name, so a re-run converges
// rather than orphaning an account and creating a second one. It is also
// globally distinct from anyone else's.
//
// 'st' (2) + labName (max 9) + uniqueString (13) = 24 exactly, the limit.
// The sanitise is belt and braces: labName is documented as lowercase
// alphanumeric, but Bicep cannot enforce a character set on a parameter, and a
// stray hyphen here would produce an invalid name rather than an obvious error.
// ---------------------------------------------------------------------------
var sanitisedLabName = toLower(replace(replace(labName, '-', ''), '_', ''))
var storageAccountName = 'st${take(sanitisedLabName, 9)}${uniqueString(resourceGroup().id)}'

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageAccountName
  location: location
  tags: labTags
  sku: {
    name: storageSkuName
  }
  // Premium file shares require the FileStorage kind; standard uses StorageV2.
  kind: isPremium ? 'FileStorage' : 'StorageV2'
  properties: {
    // ---- The Entra Kerberos toggle. See the header comment. ----
    azureFilesIdentityBasedAuthentication: {
      directoryServiceOptions: 'AADKERB'
      // No activeDirectoryProperties block: domainName/domainGuid are only
      // needed for HYBRID identities configuring ACLs through File Explorer.
      // Easy Mode is cloud-only, so they're omitted deliberately.
    }

    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Enabled'

    // Lab-scoped: the session host subnet reaches this account over the Azure
    // backbone. Locking egress down to a VNet rule or Private Link is a Hard
    // Mode item, not an oversight here.
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }

    largeFileSharesState: isPremium ? null : 'Enabled'
  }
}

resource fileServices 'Microsoft.Storage/storageAccounts/fileServices@2025-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    protocolSettings: {
      smb: {
        versions: 'SMB3.1.1'
        authenticationMethods: 'Kerberos'

        // AES-256 only — RC4 is deliberately absent.
        //
        // The April 2026 Windows update flipped the default Kerberos encryption
        // type from RC4 to AES-SHA1. Shares still relying on RC4 hit access
        // failures once that update lands on the session hosts. This has already
        // shipped; it is a present constraint, not a future one.
        kerberosTicketEncryption: 'AES-256'
        channelEncryption: 'AES-256-GCM'
      }
    }
  }
}

resource profileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2025-01-01' = {
  parent: fileServices
  name: shareName
  properties: {
    shareQuota: shareQuotaGb
    enabledProtocols: 'SMB'
    // TransactionOptimized matches FSLogix's small-random-IO profile workload.
    // Premium shares don't take an access tier.
    accessTier: isPremium ? null : 'TransactionOptimized'
  }
}

@description('Name of the FSLogix storage account.')
output storageAccountName string = storageAccount.name

@description('Resource ID of the FSLogix storage account. Consumed by Set-AvdLabFSLogixAuth.ps1 to locate the Entra app registration.')
output storageAccountId string = storageAccount.id

@description('Name of the FSLogix profile share.')
output shareName string = profileShare.name

@description('UNC path for the FSLogix VHDLocations registry value on each session host.')
output profileShareUncPath string = '\\\\${storageAccount.name}.file.${environment().suffixes.storage}\\${shareName}'
