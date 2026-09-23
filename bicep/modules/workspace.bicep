/*
  workspace.bicep — the AVD workspace, the thing a user actually subscribes to.

  The workspace is the top of the feed: a user subscribes to a workspace and sees
  whatever the application groups it references publish. The reference is stored
  here, on the workspace, which is why this module deploys AFTER appgroup.bicep
  and takes its ID as input. See the header of appgroup.bicep for why that order
  is the one that works in a single pass.

  applicationGroupReferences is a REPLACE-IN-FULL array. Deploying this module
  with a shorter list silently unpublishes whatever is missing -- the app groups
  survive, they just vanish from every user's feed. In Easy Mode there is exactly
  one app group so this is academic, but it is the same replace-in-full trap as
  the Graph `tags` collection in Set-AvdLabFSLogixAuth.ps1, and it bites the same
  way once a second app group exists.
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

@description('Azure region. Must match the host pool and application group.')
param location string = resourceGroup().location

@description('''
Resource IDs of the application groups this workspace publishes. Replace-in-full:
whatever is passed here becomes the complete set. Defaults to empty so the module
is deployable on its own, though a workspace publishing nothing is not useful.
''')
param applicationGroupIds array = []

@description('Name shown to users when they subscribe. Carries the lab name: this is the string someone reads when deciding which workspace to connect to.')
param friendlyName string = ''

@description('Description of the workspace.')
param workspaceDescription string = 'Workspace deployed by AVD Lab Kit (Easy Mode).'

@description('Tags applied to every resource in this module.')
param tags object = {}

var workspaceName = 'ws-avdlab-${labName}'
var labTags = union(tags, { 'avdlab-name': labName })
var effectiveFriendlyName = empty(friendlyName) ? 'AVD Lab Kit — ${labName}' : friendlyName

resource workspace 'Microsoft.DesktopVirtualization/workspaces@2025-10-10' = {
  name: workspaceName
  location: location
  tags: labTags
  properties: {
    friendlyName: effectiveFriendlyName
    description: workspaceDescription
    applicationGroupReferences: applicationGroupIds
  }
}

@description('Resource ID of the workspace.')
output workspaceId string = workspace.id

@description('Name of the workspace.')
output workspaceName string = workspace.name

@description('Number of application groups this workspace publishes. Zero means users see an empty feed.')
output publishedAppGroupCount int = length(applicationGroupIds)
