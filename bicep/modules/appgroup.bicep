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

@description('Azure region. Must match the host pool.')
param location string = resourceGroup().location

@description('Resource ID of the host pool this group publishes from. Output of hostpool.bicep.')
param hostPoolId string

@description('Name shown to users in the client. Carries the lab name so two labs are distinguishable in one feed.')
param friendlyName string = ''

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

var appGroupName = 'dag-avdlab-${labName}'
var labTags = union(tags, { 'avdlab-name': labName })
var effectiveFriendlyName = empty(friendlyName) ? 'AVD Lab Kit Desktop — ${labName}' : friendlyName

resource appGroup 'Microsoft.DesktopVirtualization/applicationGroups@2025-10-10' = {
  name: appGroupName
  location: location
  tags: labTags
  properties: {
    hostPoolArmPath: hostPoolId
    applicationGroupType: applicationGroupType
    friendlyName: effectiveFriendlyName
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
