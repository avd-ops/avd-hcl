/*
  scalingplan.bicep — the autoscale schedule attached to the host pool.

  A scaling plan moves a pooled host pool through four phases a day: ramp-up,
  peak, ramp-down, and off-peak. It is the most visually satisfying part of the
  lab to narrate, because you can point at hosts being deallocated and explain
  that the bill follows.

  ONE THING WILL MAKE THIS MODULE SILENTLY DO NOTHING.

  A scaling plan works by starting and stopping VMs on your behalf, so the Azure
  Virtual Desktop service principal needs the 'Desktop Virtualization Power On
  Off Contributor' role on the resource group. Without it, the plan deploys
  successfully, attaches to the host pool successfully, reports no error anywhere,
  and then never powers a host on or off.

  That grant is a role assignment, so it lives with every other role assignment in
  Add-AvdLabAssignments.ps1 rather than being scattered here. Test-AvdLabDeployment.ps1
  checks for it explicitly, because "deployed fine, does nothing" is precisely the
  failure this lab is built to make visible rather than tolerate.

  Times are supplied as 'HH:mm' strings because they come from
  orchestrator.config.json, where a human edits them. ARM wants {hour, minute}
  integers; the split happens here so the editable surface stays human-shaped.
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

@description('Resource ID of the host pool this plan drives. Output of hostpool.bicep.')
param hostPoolId string

@description('Name shown in the portal.')
param friendlyName string = ''

@description('''
IANA/Windows time zone the schedule is evaluated in. This is the single most
common misconfiguration: a plan set in the wrong zone ramps down in the middle of
the working day and looks like an outage.
''')
param timeZone string = 'Eastern Standard Time'

@description('Days this schedule applies to. Days not listed have no schedule, and hosts stay in their current state.')
param daysOfWeek array = [
  'Monday'
  'Tuesday'
  'Wednesday'
  'Thursday'
  'Friday'
]

@description('Ramp-up start, HH:mm.')
param rampUpStartTime string = '08:00'

@description('Peak start, HH:mm.')
param peakStartTime string = '09:00'

@description('Ramp-down start, HH:mm.')
param rampDownStartTime string = '17:00'

@description('Off-peak start, HH:mm.')
param offPeakStartTime string = '19:00'

@description('Percentage of hosts to have running during ramp-up.')
@minValue(0)
@maxValue(100)
param rampUpMinimumHostsPct int = 50

@description('Percentage of hosts to keep running during ramp-down and off-peak. 0 lets the pool scale to nothing when nobody is connected, which is the point of the exercise.')
@minValue(0)
@maxValue(100)
param rampDownMinimumHostsPct int = 0

@description('''
Enable the plan. Deployed disabled would be the safer default in production; here
it is on, because a scaling plan nobody switched on is an anticlimax.
''')
param scalingPlanEnabled bool = true

@description('Tags applied to every resource in this module.')
param tags object = {}

var scalingPlanName = 'sp-avdlab-${labName}'
var labTags = union(tags, { 'avdlab-name': labName })
var effectiveFriendlyName = empty(friendlyName) ? 'AVD Lab Kit weekday autoscale — ${labName}' : friendlyName

// 'HH:mm' -> { hour: int, minute: int }. Bicep has no time type, so this is the
// conversion ARM needs, done once rather than four times inline.
func toScheduleTime(value string) object => {
  hour: int(split(value, ':')[0])
  minute: int(split(value, ':')[1])
}

resource scalingPlan 'Microsoft.DesktopVirtualization/scalingPlans@2025-10-10' = {
  name: scalingPlanName
  location: location
  tags: labTags
  properties: {
    friendlyName: effectiveFriendlyName
    description: 'Weekday ramp-up/peak/ramp-down/off-peak autoscale, deployed by AVD Lab Kit.'
    timeZone: timeZone

    // Must match the host pool's type. A Pooled plan on a Personal pool is
    // rejected, which is the one mistake here that fails loudly.
    hostPoolType: 'Pooled'

    hostPoolReferences: [
      {
        hostPoolArmPath: hostPoolId
        scalingPlanEnabled: scalingPlanEnabled
      }
    ]

    schedules: [
      {
        name: 'weekday'
        daysOfWeek: daysOfWeek

        // ---- Ramp-up: morning login storm ----
        rampUpStartTime: toScheduleTime(rampUpStartTime)
        // BreadthFirst during ramp-up spreads the arriving users over the hosts
        // that are already on, rather than packing the first one and making
        // everybody's morning slow.
        rampUpLoadBalancingAlgorithm: 'BreadthFirst'
        rampUpMinimumHostsPct: rampUpMinimumHostsPct
        rampUpCapacityThresholdPct: 60

        // ---- Peak ----
        peakStartTime: toScheduleTime(peakStartTime)
        peakLoadBalancingAlgorithm: 'BreadthFirst'

        // ---- Ramp-down: consolidate and switch hosts off ----
        rampDownStartTime: toScheduleTime(rampDownStartTime)
        // DepthFirst during ramp-down is the whole trick: pack the remaining
        // sessions onto as few hosts as possible so the others can be emptied
        // and deallocated. BreadthFirst here would keep every host alive with
        // one session each and save nothing.
        rampDownLoadBalancingAlgorithm: 'DepthFirst'
        rampDownMinimumHostsPct: rampDownMinimumHostsPct
        rampDownCapacityThresholdPct: 90

        // Do not throw people off. Hosts drain as sessions end naturally.
        // Setting this true is a legitimate production choice and a hostile
        // thing to demonstrate live.
        rampDownForceLogoffUsers: false
        rampDownWaitTimeMinutes: 30
        rampDownNotificationMessage: 'This session host is shutting down. Please save your work and sign out.'
        rampDownStopHostsWhen: 'ZeroSessions'

        // ---- Off-peak ----
        offPeakStartTime: toScheduleTime(offPeakStartTime)
        offPeakLoadBalancingAlgorithm: 'DepthFirst'
      }
    ]
  }
}

@description('Resource ID of the scaling plan.')
output scalingPlanId string = scalingPlan.id

@description('Name of the scaling plan.')
output scalingPlanName string = scalingPlan.name

@description('Human-readable summary of the schedule, for the as-built report.')
output scheduleSummary string = '${join(daysOfWeek, ', ')} — ramp-up ${rampUpStartTime}, peak ${peakStartTime}, ramp-down ${rampDownStartTime}, off-peak ${offPeakStartTime} (${timeZone})'
