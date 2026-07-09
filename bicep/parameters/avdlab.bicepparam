/*
  avdlab.bicepparam — single source of truth for every Bicep parameter.

  PLACEHOLDERS ONLY IN THIS FILE (CLAUDE.md Section 14).
  Real values belong in avdlab.local.bicepparam, which is gitignored and never
  staged. Nothing here may ever be a real subscription ID, tenant ID, object ID,
  or email address. The Pester suite enforces this on every commit.

  ---------------------------------------------------------------------------
  WHY `using none`

  A .bicepparam is normally bound to exactly one template, and may only assign
  parameters that template declares. One file spanning eight modules is therefore
  impossible -- Bicep rejects it with BCP259 ("assigned in the params file without
  being declared in the Bicep file"). `using none` decouples the file from any
  single template, so it compiles standalone to a deploymentParameters JSON
  document. Deploy-AvdLab.ps1 reads that document and passes each module only the
  parameters that module declares, via -TemplateParameterObject.

  The trade is real: nothing type-checks these values against the modules at
  compile time, so a typo'd parameter name would be silently ignored rather than
  rejected. tests/AvdLab.Tests.ps1 closes that hole by asserting that every name
  here is declared by at least one module, and that every module's required
  parameters are satisfied either here or by the orchestrator at runtime.

  ---------------------------------------------------------------------------
  THE NAME-COLLISION HAZARD, AND WHY SOME PARAMETERS ARE ABSENT

  This file is flat, but parameter names are module-scoped. `friendlyName` means
  three different things in hostpool.bicep, appgroup.bicep, and workspace.bicep.
  Assigning it once here would splat the same string into all three.

  So: only genuinely lab-wide values (location, tags) or unambiguously-named ones
  (hostPoolName, vnetCidr) live here. Anything whose name repeats across modules
  with a different meaning -- friendlyName, description -- is deliberately omitted
  and left to each module's own default. If you need to override one, give the
  module's parameter a unique name first.

  Values the orchestrator injects at runtime are also absent by design: module
  outputs (hostPoolId, applicationGroupIds), generated secrets (the session host
  admin password, Section 5), and time-derived defaults (tokenExpirationTime).
*/

using none

// ---------------------------------------------------------------------------
// Lab-wide
// ---------------------------------------------------------------------------

// Region for every resource. Must support Entra Kerberos for Azure Files (Section 6).
param location = 'eastus2'

// Applied to every resource in every module. Standard tagging is a v1.x item (Section 18).
param tags = {
  workload: 'avd-lab-kit'
  environment: 'lab'
  managedBy: 'avd-lab-kit'
}

// ---------------------------------------------------------------------------
// network.bicep
// ---------------------------------------------------------------------------

param vnetName = 'vnet-avdlab'
param vnetCidr = '10.20.0.0/24'
param subnetName = 'snet-avdlab-hosts'
param subnetCidr = '10.20.0.0/26'
param nsgName = 'nsg-avdlab-hosts'

// The lab's single public IP, and it belongs to the NAT gateway -- never to a
// session host. Outbound only. See Section 2/8: default outbound access retired
// 2026-03-31, so egress is now something you ask for explicitly.
param natGatewayName = 'natgw-avdlab'
param publicIpName = 'pip-avdlab-natgw'

// ---------------------------------------------------------------------------
// storage.bicep — FSLogix profile containers
// ---------------------------------------------------------------------------

// Globally unique, 3-24 chars, lowercase alphanumeric only. Change this before
// deploying: the value below will already be taken.
param storageAccountName = 'stavdlabfslogix'
param shareName = 'profiles'
param shareQuotaGb = 1024
param storageSkuName = 'Standard_LRS'

// ---------------------------------------------------------------------------
// hostpool.bicep / workspace.bicep / appgroup.bicep
// ---------------------------------------------------------------------------

param hostPoolName = 'hp-avdlab-pooled'
param workspaceName = 'ws-avdlab'
param appGroupName = 'dag-avdlab'

param loadBalancerType = 'BreadthFirst'
param maxSessionLimit = 4

// ---------------------------------------------------------------------------
// sessionhosts.bicep — not yet built (Jul 15-16)
// ---------------------------------------------------------------------------

param sessionHostCount = 3
param vmSize = 'Standard_D4ads_v5'
param imagePublisher = 'MicrosoftWindowsDesktop'
param imageOffer = 'windows-11'

// Verified 2026-07-09. Supported to 2028-10-10. Alternative: win11-24h2-avd (to
// 2027-10-12). Do NOT use win11-23h2-avd -- end of updates 2026-11-10, i.e. weeks
// after the September demo. Re-verify at the Section 18 drift check.
param imageSku = 'win11-25h2-avd'

// ---------------------------------------------------------------------------
// monitoring.bicep — not yet built (Jul 15-16)
// ---------------------------------------------------------------------------

param logAnalyticsWorkspaceName = 'log-avdlab-weuc'

// Free-tier default, deliberately not extended. This is a short-lived lab, not a
// production workspace (Section 18).
param logAnalyticsRetentionDays = 30

param budgetAmount = 50

// PLACEHOLDER. Real address goes in avdlab.local.bicepparam (Section 14).
param budgetAlertEmail = '<YOUR_EMAIL>'

// 'AlertOnly' is the v1.0 default and a no-op beyond the budget alert.
// 'AlertAndDelete' is designed (Section 18) but not built until v1.x.
param costGuardrailMode = 'AlertOnly'
