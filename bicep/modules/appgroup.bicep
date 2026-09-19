/*
  appgroup.bicep — the Desktop application group published from the host pool.

  An application group is what users are actually assigned to. A Desktop app group
  publishes the whole session desktop; a RailApplications group publishes
  individual apps. Easy Mode takes Desktop.

  DEPLOYMENT ORDER, AND WHY IT IS NOT WHAT THE SPEC ORIGINALLY SAID.
  The workspace <-> app group link lives on the WORKSPACE as
  `applicationGroupReferences`, not on the app group. So the workspace cannot be
  created "then associated" without a second write to it. Creating the app group
  first, and passing its ID into workspace.bicep, links the two in a single pass:

      hostpool.bicep -> appgroup.bicep -> workspace.bicep

  The intuitive order (workspace, then app group) would need workspace.bicep
  deployed twice -- once empty, once with the reference. Same end state, one extra
  deployment, and a window where the workspace exists publishing nothing.

  Note there is NO role assignment here. Assigning users/groups to this app group
  is a Graph/RBAC operation and lives in Add-AvdLabAssignments.ps1, together with
  the Storage File Data SMB Share Contributor grant the FSLogix share needs
  for cloud-only identities. Keeping "who may access what" in one place beats splitting it
  across a Bicep module and a script.
*/

@description('Name of the desktop application group.')
@minLength(3)
@maxLength(64)
param appGroupName string

@description('Azure region. Must match the host pool.')
param location string = resourceGroup().location

@description('Resource ID of the host pool this group publishes from. Output of hostpool.bicep.')
param hostPoolId string

@description('Name shown to users in the client.')
param friendlyName string = 'AVD Lab Kit Desktop'

@description('Description of the application group.')
param appGroupDescription string = 'Full desktop published by AVD Lab Kit (Easy Mode).'

@description('''
Desktop publishes the full session desktop. Must agree with the host pool's
preferredAppGroupType -- ARM will accept a mismatch and users will then find the
resource missing from their client feed.
''')
@allowed([
  'Desktop'
  'RemoteApp'
])
param applicationGroupType string = 'Desktop'

@description('Tags applied to every resource in this module.')
param tags object = {}

resource appGroup 'Microsoft.DesktopVirtualization/applicationGroups@2025-10-10' = {
  name: appGroupName
  location: location
  tags: tags
  properties: {
    hostPoolArmPath: hostPoolId
    applicationGroupType: applicationGroupType
    friendlyName: friendlyName
    description: appGroupDescription
  }
}

/*
  NO `applicationGroups/desktops` RESOURCE HERE, DELIBERATELY.

  A Desktop app group is born with exactly one desktop, always named
  'SessionDesktop'. It cannot be created or deleted, only renamed -- and ARM
  exposes it as read-only, so Bicep refuses to deploy it (BCP245: "can only be
  used with the 'existing' keyword"). An earlier draft of this module declared it
  anyway to set a friendly name; `az bicep build` emitted a warning and produced a
  template that would not have done anything.

  Renaming the published desktop therefore belongs in the PowerShell layer:
      Update-AzWvdDesktop -ResourceGroupName ... -ApplicationGroupName ... \
                          -Name SessionDesktop -FriendlyName 'Lab Desktop'
  It is cosmetic. Users see "SessionDesktop" in their feed without it.
*/

@description('Resource ID of the application group. Passed to workspace.bicep and to Add-AvdLabAssignments.ps1.')
output appGroupId string = appGroup.id

@description('Name of the application group.')
output appGroupName string = appGroup.name
