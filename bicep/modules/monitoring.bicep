/*
  monitoring.bicep — Log Analytics, AVD Insights plumbing, and the cost guardrail.

  Two unrelated jobs share this module because they share a motive: knowing what
  the lab is doing while it is running.

    1. TELEMETRY. A Log Analytics workspace, diagnostic settings on the three AVD
       control-plane resources, and a Data Collection Rule delivered to each
       session host by the Azure Monitor Agent. Together these are what make the
       AVD Insights workbook light up.

    2. COST. An Azure Budget scoped to this resource group, wired to an action
       group that emails you. Alert only -- nothing here deletes anything.

  THE ACTUAL COST RISK IS TIME, NOT INGESTION. A few session hosts logging for a
  few hours is rounding-error money. What costs real money is a lab left running
  for three weeks because the demo ended and nobody ran the teardown. The budget
  alert exists for that, which is why it is scoped to the resource group and
  measured in days rather than tuned to the diagnostic category list.

  DEPLOY ORDER: this module runs AFTER sessionhosts.bicep. The agent and DCR
  association attach to VMs that must already exist. It is still deployable on its
  own -- pass no session host names and it deploys the workspace and budget alone.
*/

@description('Azure region.')
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

@description('''
Retention in days. 30 is the included-at-no-cost floor and is deliberately not
extended: this is a short-lived lab, not a production workspace, and a 90-day
retention on a workspace nobody deletes is a slow leak.
''')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 30

@description('''
Names of the session hosts to attach the Azure Monitor Agent and Data Collection
Rule to. Output of sessionhosts.bicep. Empty deploys the workspace and budget
without touching any VM, which is what makes this module standalone-deployable.
''')
param sessionHostNames array = []

@description('Monthly budget in your billing currency, scoped to this resource group.')
@minValue(1)
param budgetAmount int = 50

@description('Email address for the budget alert. Must be a real address in your local override, never in the tracked parameter file.')
param budgetAlertEmail string

@description('''
Cost guardrail behaviour.

Only AlertOnly is implemented. AlertAndDelete is a designed-but-unbuilt mode that
would add an Automation Account, a runbook, and a second, much higher budget
threshold to trigger teardown. Deploy-AvdLab.ps1 rejects AlertAndDelete outright
rather than letting it deploy as a silent no-op -- a cost guardrail you believe in
but that does not exist is worse than no guardrail at all.
''')
@allowed([
  'AlertOnly'
  'AlertAndDelete'
])
param costGuardrailMode string = 'AlertOnly'

@description('First day of the budget period, YYYY-MM-01. Must be the first of a month.')
param budgetStartDate string = utcNow('yyyy-MM-01')

@description('Tags applied to every resource in this module.')
param tags object = {}

// ---------------------------------------------------------------------------
// Derived names. The three AVD resources are referenced as `existing`, so these
// must match exactly what the other modules built -- which is precisely why
// they are derived from one lab name rather than passed in separately. A
// mismatch here does not fail loudly: the diagnostic setting simply attaches to
// nothing and the Insights workbook stays empty.
// ---------------------------------------------------------------------------
var logAnalyticsWorkspaceName = 'log-avdlab-${labName}'
var hostPoolName = 'hp-avdlab-${labName}'
var appGroupName = 'dag-avdlab-${labName}'
var workspaceName = 'ws-avdlab-${labName}'
var dataCollectionRuleName = 'dcr-avdlab-${labName}'
var actionGroupName = 'ag-avdlab-${labName}'
var budgetName = 'budget-avdlab-${labName}'

// Action group short names are capped at 12 characters and this is what shows
// up in the alert email subject. 'avd' (3) + labName (max 9) = 12 exactly.
var actionGroupShortName = take('avd${labName}', 12)

var labTags = union(tags, { 'avdlab-name': labName })

// ---------------------------------------------------------------------------
// Log Analytics workspace
// ---------------------------------------------------------------------------
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: labTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logAnalyticsRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ---------------------------------------------------------------------------
// Diagnostic settings on the AVD control plane
//
// Category choice is deliberate. These six are what the AVD Insights workbook
// reads. NetworkData and ConnectionGraphicsData are deliberately OFF: they are
// far higher volume and answer production performance questions ("why is this
// user's session choppy") that a short-lived lab does not ask.
// ---------------------------------------------------------------------------
resource hostPool 'Microsoft.DesktopVirtualization/hostPools@2025-10-10' existing = {
  name: hostPoolName
}

resource appGroup 'Microsoft.DesktopVirtualization/applicationGroups@2025-10-10' existing = {
  name: appGroupName
}

resource avdWorkspace 'Microsoft.DesktopVirtualization/workspaces@2025-10-10' existing = {
  name: workspaceName
}

var hostPoolLogCategories = [
  'Checkpoint'
  'Error'
  'Management'
  'Connection'
  'HostRegistration'
  'AgentHealthStatus'
]

// App groups and workspaces emit a narrower set; asking for a category a resource
// does not publish is rejected outright rather than ignored.
var appGroupLogCategories = [
  'Checkpoint'
  'Error'
  'Management'
]

var avdWorkspaceLogCategories = [
  'Checkpoint'
  'Error'
  'Management'
  'Feed'
]

resource hostPoolDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: hostPool
  name: 'diag-avdlab-hostpool'
  properties: {
    workspaceId: logAnalytics.id
    logs: [for category in hostPoolLogCategories: {
      category: category
      enabled: true
    }]
  }
}

resource appGroupDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: appGroup
  name: 'diag-avdlab-appgroup'
  properties: {
    workspaceId: logAnalytics.id
    logs: [for category in appGroupLogCategories: {
      category: category
      enabled: true
    }]
  }
}

resource avdWorkspaceDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: avdWorkspace
  name: 'diag-avdlab-workspace'
  properties: {
    workspaceId: logAnalytics.id
    logs: [for category in avdWorkspaceLogCategories: {
      category: category
      enabled: true
    }]
  }
}

// ---------------------------------------------------------------------------
// Data Collection Rule — what the agent gathers from each session host
//
// The control-plane diagnostics above tell you what the AVD *service* did. This
// tells you what the *machines* are doing. AVD Insights needs both, and the
// half that gets forgotten is always this one, because the workbook renders
// without it and simply shows blank host-performance panels.
// ---------------------------------------------------------------------------
resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: dataCollectionRuleName
  location: location
  tags: labTags
  kind: 'Windows'
  properties: {
    description: 'Performance counters and event logs required by the AVD Insights workbook.'
    dataSources: {
      performanceCounters: [
        {
          name: 'avdPerfCounters'
          streams: [
            'Microsoft-Perf'
          ]
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            '\\LogicalDisk(C:)\\% Free Space'
            '\\LogicalDisk(C:)\\Avg. Disk Queue Length'
            '\\LogicalDisk(C:)\\Current Disk Queue Length'
            '\\Memory\\Available Mbytes'
            '\\Memory\\Page Faults/sec'
            '\\Memory\\Pages/sec'
            '\\Memory\\% Committed Bytes In Use'
            '\\PhysicalDisk(*)\\Avg. Disk Queue Length'
            '\\PhysicalDisk(*)\\Avg. Disk sec/Read'
            '\\PhysicalDisk(*)\\Avg. Disk sec/Transfer'
            '\\PhysicalDisk(*)\\Avg. Disk sec/Write'
            '\\Processor Information(_Total)\\% Processor Time'
            '\\User Input Delay per Process(*)\\Max Input Delay'
            '\\User Input Delay per Session(*)\\Max Input Delay'
            '\\RemoteFX Network(*)\\Current TCP RTT'
            '\\RemoteFX Network(*)\\Current UDP Bandwidth'
            '\\Terminal Services(*)\\Active Sessions'
            '\\Terminal Services(*)\\Inactive Sessions'
            '\\Terminal Services(*)\\Total Sessions'
          ]
        }
      ]
      windowsEventLogs: [
        {
          name: 'avdEventLogs'
          streams: [
            'Microsoft-Event'
          ]
          xPathQueries: [
            'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Admin!*'
            'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational!*'
            'System!*'
            'Application!*[System[(Level=2 or Level=3)]]'
            // FSLogix writes its own operational channels. When a profile fails
            // to load, this is where it says so -- and given the Entra Kerberos
            // dependency, it is the first place to look.
            'Microsoft-FSLogix-Apps/Operational!*'
            'Microsoft-FSLogix-Apps/Admin!*'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalytics.id
          name: 'laDestination'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-Perf'
        ]
        destinations: [
          'laDestination'
        ]
      }
      {
        streams: [
          'Microsoft-Event'
        ]
        destinations: [
          'laDestination'
        ]
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Azure Monitor Agent + DCR association, per session host
//
// Both are needed and they fail differently: no agent means no data at all; an
// agent with no association means an agent sitting idle collecting nothing.
// ---------------------------------------------------------------------------
resource existingSessionHosts 'Microsoft.Compute/virtualMachines@2024-07-01' existing = [for name in sessionHostNames: {
  name: name
}]

resource azureMonitorAgent 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = [for (name, i) in sessionHostNames: {
  parent: existingSessionHosts[i]
  name: 'AzureMonitorWindowsAgent'
  location: location
  tags: labTags
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorWindowsAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
  }
}]

resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = [for (name, i) in sessionHostNames: {
  scope: existingSessionHosts[i]
  name: 'dcra-avdlab-insights'
  properties: {
    description: 'Associates the AVD Insights data collection rule with this session host.'
    dataCollectionRuleId: dataCollectionRule.id
  }
  dependsOn: [
    azureMonitorAgent[i]
  ]
}]

// ---------------------------------------------------------------------------
// Cost guardrail — action group + budget, scoped to this resource group
// ---------------------------------------------------------------------------
resource budgetActionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  // Action groups are a global resource. 'global' is correct here and a region
  // name is rejected.
  location: 'global'
  tags: labTags
  properties: {
    // Max 12 characters, and it is what shows up in the alert email subject.
    groupShortName: actionGroupShortName
    enabled: true
    emailReceivers: [
      {
        name: 'budgetOwner'
        emailAddress: budgetAlertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

resource budget 'Microsoft.Consumption/budgets@2023-05-01' = {
  name: budgetName
  properties: {
    category: 'Cost'
    amount: budgetAmount
    timeGrain: 'Monthly'
    timePeriod: {
      // Must be the first of a month. Deploying at RG scope scopes the budget to
      // this resource group automatically -- no filter needed, and no way for it
      // to accidentally watch the whole subscription.
      startDate: budgetStartDate
    }
    notifications: {
      // Actual spend past 80%: you are burning more than expected.
      actualOver80: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        thresholdType: 'Actual'
        // Required by the API even when the alert routes through an action
        // group. Empty is valid and keeps the recipient defined in exactly one
        // place -- duplicating the address here is how the two drift apart.
        contactEmails: []
        contactGroups: [
          budgetActionGroup.id
        ]
      }
      // Forecast past 100%: the lab is still running and will blow the budget if
      // left alone. This is the one that catches "the demo finished on Tuesday
      // and nobody ran the teardown", which is the actual failure mode.
      forecastedOver100: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        thresholdType: 'Forecasted'
        contactEmails: []
        contactGroups: [
          budgetActionGroup.id
        ]
      }
    }
  }
}

@description('Resource ID of the Log Analytics workspace.')
output logAnalyticsWorkspaceId string = logAnalytics.id

@description('Name of the Log Analytics workspace.')
output logAnalyticsWorkspaceName string = logAnalytics.name

@description('Customer ID (workspace GUID) of the Log Analytics workspace.')
output logAnalyticsCustomerId string = logAnalytics.properties.customerId

@description('Resource ID of the AVD Insights data collection rule.')
output dataCollectionRuleId string = dataCollectionRule.id

@description('Number of session hosts the agent and data collection rule were attached to.')
output monitoredSessionHostCount int = length(sessionHostNames)

@description('Resource ID of the budget.')
output budgetId string = budget.id

@description('Whether the selected cost guardrail mode is actually implemented by this module. AlertAndDelete is designed but not built.')
output costGuardrailImplemented bool = (costGuardrailMode == 'AlertOnly')
