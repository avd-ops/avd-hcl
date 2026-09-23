/*
  avdlab.bicepparam — single source of truth for every Bicep parameter.

  PLACEHOLDERS ONLY IN THIS FILE.
  Real values belong in avdlab.local.bicepparam, which is gitignored and never
  staged. Nothing here may ever be a real subscription ID, tenant ID, object ID,
  or email address. The Pester suite enforces this on every commit, and the
  gitleaks hook enforces it again before one can be written. See CONTRIBUTING.md.

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
  four different things across hostpool, appgroup, workspace and scalingplan.
  Assigning it once here would splat the same string into all four.

  So: only genuinely lab-wide values (location, tags, labName) or unambiguous
  ones (vnetCidr, vmSize) live here. Anything whose name repeats with a
  DIFFERENT meaning -- friendlyName above all -- is deliberately omitted and
  left to each module's own default. To override one, give that module's
  parameter a unique name first.

  ---------------------------------------------------------------------------
  RESOURCE NAMES ARE NOT HERE, AND THAT IS DELIBERATE

  Every resource name derives from `labName` inside the module that creates it,
  following <resourceType>-avdlab-<labName>. They are not parameters, so they
  cannot be overridden.

  That is a deliberate trade. Overridable names would mean two sources of truth
  about what a lab's resources are called, and the management layer identifies a
  lab by name alone -- it has to be able to work out what the host pool is called
  from the lab name and nothing else. The storage account goes further and is
  derived with uniqueString(), because its name must be globally unique; see
  storage.bicep for why a predictable one is a trap.

  Values the orchestrator injects at runtime are also absent by design: module
  outputs (hostPoolId, subnetId, applicationGroupIds, sessionHostNames),
  generated secrets (the session host admin password, the registration token),
  and time-derived defaults (tokenExpirationTime, budgetStartDate).
*/

using none

// ---------------------------------------------------------------------------
// Lab-wide
// ---------------------------------------------------------------------------

// Identifies this lab. Every resource name derives from it, so changing it
// deploys an entirely separate lab rather than renaming this one.
//
// 3-9 characters, lowercase letters and digits. The ceiling is the 15-character
// Windows computer name limit: 'vm-' + labName + '-' + a two-digit index.
//
// Defaults to 'lab' so an existing clone keeps working without edits.
param labName = 'lab'

// Region for every resource. Must support Microsoft Entra Kerberos for Azure Files.
param location = 'eastus2'

// Applied to every resource in every module.
param tags = {
  workload: 'avd-lab-kit'
  environment: 'lab'
  managedBy: 'avd-lab-kit'
}

// ---------------------------------------------------------------------------
// network.bicep
// ---------------------------------------------------------------------------

param vnetCidr = '10.20.0.0/24'
param subnetCidr = '10.20.0.0/26'

// Note there is no public IP parameter: the lab's single public IP belongs to
// the NAT gateway, never to a session host, and its name is derived like every
// other. Default outbound access was retired on 2026-03-31, so egress is now
// something you ask for explicitly.

// ---------------------------------------------------------------------------
// storage.bicep — FSLogix profile containers
// ---------------------------------------------------------------------------

// The storage account name is derived in storage.bicep from labName plus
// uniqueString(resourceGroup().id) -- globally unique without being guessable,
// and deterministic so a re-run converges. Nothing to set here.
param shareName = 'profiles'
param shareQuotaGb = 1024
param storageSkuName = 'Standard_LRS'

// ---------------------------------------------------------------------------
// hostpool.bicep / appgroup.bicep / workspace.bicep
// ---------------------------------------------------------------------------

param loadBalancerType = 'BreadthFirst'
param maxSessionLimit = 4

// ---------------------------------------------------------------------------
// sessionhosts.bicep
// ---------------------------------------------------------------------------

param sessionHostCount = 3
param vmSize = 'Standard_D4ads_v5'
param adminUsername = 'avdlabadmin'

param imagePublisher = 'MicrosoftWindowsDesktop'
param imageOffer = 'windows-11'

// Must be an -avd SKU: those are the Enterprise multi-session editions. Verify
// the current SKU before a deployment you care about rather than trusting this
// value -- image SKUs go out of support on a schedule, and the failure is a
// session host fleet quietly running an unpatched build.
//   win11-25h2-avd   supported to 2028-10-10  (this one)
//   win11-24h2-avd   supported to 2027-10-12
param imageSku = 'win11-25h2-avd'

// ---------------------------------------------------------------------------
// monitoring.bicep
// ---------------------------------------------------------------------------

// The included-at-no-cost floor, deliberately not extended. This is a
// short-lived lab, not a production workspace.
param logAnalyticsRetentionDays = 30

param budgetAmount = 50

// PLACEHOLDER. Real address goes in avdlab.local.bicepparam.
param budgetAlertEmail = '<YOUR_EMAIL>'

// 'AlertOnly' is the only implemented mode. 'AlertAndDelete' is designed but not
// built, and Deploy-AvdLab.ps1 rejects it rather than letting it deploy as a
// silent no-op.
param costGuardrailMode = 'AlertOnly'

// ---------------------------------------------------------------------------
// scalingplan.bicep
//
// Schedule times (time zone, days, ramp-up/peak/ramp-down/off-peak) live in
// orchestrator.config.json instead, so they can be adjusted without touching
// Bicep. The orchestrator passes them through at deployment time.
// ---------------------------------------------------------------------------

param rampUpMinimumHostsPct = 50
param rampDownMinimumHostsPct = 0
