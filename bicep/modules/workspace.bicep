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

@description('Name of the workspace.')
@minLength(3)
@maxLength(64)
param workspaceName string

@description('Azure region. Must match the host pool and application group.')
param location string = resourceGroup().location

@description('''
Resource IDs of the application groups this workspace publishes. Replace-in-full:
whatever is passed here becomes the complete set. Defaults to empty so the module
is deployable on its own, though a workspace publishing nothing is not useful.
''')
param applicationGroupIds array = []

@description('Name shown to users when they subscribe.')
param friendlyName string = 'AVD Lab Kit'

@description('Description of the workspace.')
param workspaceDescription string = 'Workspace deployed by AVD Lab Kit (Easy Mode).'

@description('Tags applied to every resource in this module.')
param tags object = {}

resource workspace 'Microsoft.DesktopVirtualization/workspaces@2025-10-10' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    friendlyName: friendlyName
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
