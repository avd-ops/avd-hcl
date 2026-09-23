#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Az.Accounts'; ModuleVersion = '2.0.0' }
#Requires -Modules @{ ModuleName = 'Az.Resources'; ModuleVersion = '6.0.0' }

<#
.SYNOPSIS
    Deploys the AVD lab end to end, one Bicep module at a time, narrating as it goes.

.DESCRIPTION
    A thin orchestrator around eight Bicep modules. Deliberately thin: everything
    that is a clean ARM resource lives in Bicep, and this script exists only for
    the things that genuinely are not -- Microsoft Graph calls, sequencing, and
    the running commentary that makes a live demo watchable.

    WHY EIGHT DEPLOYMENTS INSTEAD OF ONE main.bicep
    One monolithic template would be shorter and would deploy the same resources.
    It would also be a black box for ninety seconds followed by either success or
    a wall of red. Deploying phase by phase means you can narrate what is
    happening, and when something fails you know which phase failed without
    reading a correlation ID.

    THE TRANSCRIPT IS THE PRODUCT, NOT THE SCROLLBACK
    Every step appends a structured record to a JSON Lines transcript. On success
    New-AvdLabReport.ps1 renders it as an as-built document; on failure the catch
    block renders it as an evidence bundle. Console output is for the room; the
    transcript is what survives the terminal closing.

    ORDERING NOTES THAT ARE NOT OBVIOUS
      * Storage is deployed before the host pool so the Entra Kerberos app
        registration has time to appear while other things happen.
      * The app group is deployed BEFORE the workspace. The link between them is
        stored on the workspace, so building the app group first lets one
        deployment establish both sides. The reverse order needs the workspace
        deployed twice.
      * Monitoring runs after session hosts because the agent and data collection
        rule attach to VMs that must already exist.
      * Assignments run late because they grant access to things that must exist.

.PARAMETER ResourceGroupName
    Resource group to deploy into. Created if absent. Everything lives here, which
    is what makes teardown a single call.

.PARAMETER ConfigPath
    Orchestrator config. Defaults to orchestrator.local.config.json when present,
    otherwise the tracked orchestrator.config.json.

.PARAMETER ParameterFile
    Bicep parameter file. Defaults to avdlab.local.bicepparam when present,
    otherwise the tracked avdlab.bicepparam.

.PARAMETER Validate
    Full dry run. Every module is evaluated with what-if and nothing is changed.
    Graph steps and assignments report what they would do and stop. Use this to
    rehearse the talk track without touching Azure.

.PARAMETER SkipFSLogix
    Deploy without FSLogix profile containers. The documented fallback: if Entra
    Kerberos will not cooperate, the host pool, load balancing, autoscale and app
    group all still work and profiles simply become local and non-roaming. Better
    than losing the whole demo to one blocked dependency.

.EXAMPLE
    ./Deploy-AvdLab.ps1 -ResourceGroupName rg-avdlab -Validate

.EXAMPLE
    ./Deploy-AvdLab.ps1 -ResourceGroupName rg-avdlab
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[-\w\._\(\)]{1,90}$')]
    [string]$ResourceGroupName,

    [string]$ConfigPath,
    [string]$ParameterFile,
    [string]$Location,

    [switch]$Validate,
    [switch]$SkipFSLogix,

    [string]$ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:StartedUtc = (Get-Date).ToUniversalTime()
$script:RunId = $StartedUtc.ToString('yyyyMMdd-HHmmss')
$script:Steps = [System.Collections.Generic.List[object]]::new()
$script:Outputs = [ordered]@{}
$script:CurrentStep = 'startup'
$script:NarrationEnabled = $true
$script:StepDelaySeconds = 0

# ---------------------------------------------------------------------------
# Logging
#
# Two audiences, one call. The console line is written to be read aloud
# ("Deploying network module... done in 24s"); the JSON Lines record is written
# to be parsed by New-AvdLabReport.ps1 and carries the resource IDs, outputs and
# timings the console line deliberately leaves out.
# ---------------------------------------------------------------------------
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][ValidateSet('Start', 'Success', 'Info', 'Warning', 'Failure', 'Skipped')][string]$Status,
        [Parameter(Mandatory)][string]$Message,
        [hashtable]$Data,
        [double]$DurationSeconds
    )

    $record = [ordered]@{
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
        runId     = $script:RunId
        step      = $Step
        status    = $Status
        message   = $Message
    }
    if ($PSBoundParameters.ContainsKey('DurationSeconds')) { $record.durationSeconds = [math]::Round($DurationSeconds, 1) }
    if ($Data) { $record.data = $Data }

    $script:Steps.Add([pscustomobject]$record)

    if ($script:LogFile) {
        ($record | ConvertTo-Json -Depth 10 -Compress) | Add-Content -Path $script:LogFile -Encoding utf8
    }

    $glyph, $colour = switch ($Status) {
        'Start' { '  >', 'Cyan' }
        'Success' { '  [ok]', 'Green' }
        'Info' { '   -', 'Gray' }
        'Warning' { '  [!]', 'Yellow' }
        'Failure' { '  [FAILED]', 'Red' }
        'Skipped' { '  [skip]', 'DarkGray' }
    }
    $suffix = if ($PSBoundParameters.ContainsKey('DurationSeconds')) { " ({0:n0}s)" -f $DurationSeconds } else { '' }
    Write-Host ('{0} {1}{2}' -f $glyph, $Message, $suffix) -ForegroundColor $colour
}

function Write-Phase {
    param([Parameter(Mandatory)][string]$Title)
    Write-Host ''
    Write-Host "== $Title" -ForegroundColor White
    if ($script:NarrationEnabled -and $script:StepDelaySeconds -gt 0) {
        Start-Sleep -Seconds $script:StepDelaySeconds
    }
}

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
function Resolve-LabFile {
    <#
        Prefers the gitignored local override, falls back to the tracked file.
        This is the mechanism that lets the tracked copies hold placeholders
        forever: if you have a local file, it wins, and nothing needs editing.
    #>
    param(
        [Parameter(Mandatory)][string]$Explicit,
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][string]$TrackedPath
    )

    if ($Explicit) {
        if (-not (Test-Path $Explicit)) { throw "File not found: $Explicit" }
        return (Resolve-Path $Explicit).Path
    }
    if (Test-Path $LocalPath) { return (Resolve-Path $LocalPath).Path }
    if (Test-Path $TrackedPath) { return (Resolve-Path $TrackedPath).Path }
    throw "Neither $LocalPath nor $TrackedPath exists."
}

function Get-BicepCommand {
    <#
        The parameter file uses `using none`, so it must be compiled to JSON
        before anything can read it -- and that needs the Bicep CLI, either
        standalone or via the az wrapper. Resolved once, loudly, rather than
        failing three phases in with a confusing error.
    #>
    if (Get-Command bicep -ErrorAction SilentlyContinue) { return @{ Exe = 'bicep'; Prefix = @() } }
    if (Get-Command az -ErrorAction SilentlyContinue) { return @{ Exe = 'az'; Prefix = @('bicep') } }
    throw @'
Bicep CLI not found. Install it with one of:
    az bicep install
    winget install Microsoft.Bicep
It is needed to compile the parameter file, which uses `using none` and therefore
has no template to bind to.
'@
}

function Invoke-Bicep {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $cmd = $script:BicepCommand
    $all = @($cmd.Prefix) + $Arguments
    $output = & $cmd.Exe @all 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "bicep $($all -join ' ') failed:`n$($output -join "`n")"
    }
    return ($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join "`n"
}

function Get-LabResourceName {
    <#
        Derives a resource name from the lab name, mirroring exactly what the
        Bicep modules do. This duplication is deliberate and load-bearing: the
        orchestrator has to know what the host pool is called before it has
        deployed anything, so it cannot simply read a module output.

        The Pester suite asserts these strings match the modules' own
        expressions, because a silent divergence here would be poisonous -- the
        orchestrator would look for resources that exist under another name and
        report them missing.

        NOT here: the storage account. Its name is built with uniqueString(),
        an ARM function with no PowerShell equivalent, so it is read from
        storage.bicep's output instead.
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('hostPool', 'appGroup', 'workspace', 'logAnalytics', 'scalingPlan', 'vnet', 'resourceGroup')]
        [string]$Kind,
        [Parameter(Mandatory)][string]$LabName
    )
    $prefix = @{
        hostPool      = 'hp-avdlab'
        appGroup      = 'dag-avdlab'
        workspace     = 'ws-avdlab'
        logAnalytics  = 'log-avdlab'
        scalingPlan   = 'sp-avdlab'
        vnet          = 'vnet-avdlab'
        resourceGroup = 'rg-avdlab'
    }[$Kind]
    return "$prefix-$LabName"
}

function Assert-LabName {
    <#
        Bicep can constrain a parameter's length but not its character set, so a
        lab name with a capital letter or a hyphen compiles happily and then
        produces an invalid storage account name several phases later. Validate
        it here, once, before anything is created.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$LabName)

    if ($LabName -cnotmatch '^[a-z0-9]{3,9}$') {
        throw @"
labName '$LabName' is not valid.

It must be 3-9 characters, lowercase letters and digits only.

The 9-character ceiling is the Windows computer name limit: session hosts are
named vm-<labName>-<n>, and 'vm-' + 9 + '-' + a two-digit index is exactly 15.
A longer name is rejected by ARM at the session host phase, long after the
network and storage are built.
"@
    }
}

function Get-LabParameters {
    <#
        Compiles avdlab.bicepparam to a deploymentParameters document and flattens
        it to name -> value. `using none` means Bicep does not check these against
        any module, so the Pester suite carries that burden instead.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $json = Invoke-Bicep -Arguments @('build-params', $Path, '--stdout') | ConvertFrom-Json
    $parameters = ($json.parametersJson | ConvertFrom-Json).parameters

    $flat = @{}
    foreach ($property in $parameters.PSObject.Properties) {
        $flat[$property.Name] = $property.Value.value
    }
    return $flat
}

function Get-ModuleParameterName {
    <#
        Which parameters does this module actually declare? Read from the compiled
        template rather than regexed out of the source, so a multi-line @description
        or an unusual type annotation cannot fool it.
    #>
    param([Parameter(Mandatory)][string]$ModulePath)

    if (-not $script:ModuleParamCache) { $script:ModuleParamCache = @{} }
    if ($script:ModuleParamCache.ContainsKey($ModulePath)) { return $script:ModuleParamCache[$ModulePath] }

    $template = Invoke-Bicep -Arguments @('build', $ModulePath, '--stdout') | ConvertFrom-Json
    $names = if ($template.PSObject.Properties['parameters']) {
        @($template.parameters.PSObject.Properties.Name)
    }
    else { @() }

    $script:ModuleParamCache[$ModulePath] = $names
    return $names
}

function Invoke-LabDeployment {
    <#
        One module, one deployment. Takes the flat parameter set, keeps only what
        this module declares, layers on runtime values (module outputs, generated
        secrets), and deploys -- or runs what-if when -Validate is set.

        Splatting only the declared parameters is what makes a single flat
        parameter file workable across eight modules. Passing the whole set would
        fail with "parameter not declared in the template" on every module.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Module,
        [Parameter(Mandatory)][string]$Description,
        [hashtable]$Runtime = @{}
    )

    $modulePath = Join-Path $script:RepoRoot "bicep/modules/$Module.bicep"
    if (-not (Test-Path $modulePath)) { throw "Module not found: $modulePath" }

    $declared = Get-ModuleParameterName -ModulePath $modulePath
    $splat = @{}
    foreach ($name in $declared) {
        if ($Runtime.ContainsKey($name)) { $splat[$name] = $Runtime[$name] }
        elseif ($script:LabParameters.ContainsKey($name)) { $splat[$name] = $script:LabParameters[$name] }
    }

    # A runtime value the module does not declare is almost always a wiring bug --
    # the orchestrator computed something and handed it to the wrong module. Say so
    # rather than silently dropping it.
    $ignored = $Runtime.Keys | Where-Object { $_ -notin $declared }
    if ($ignored) {
        Write-Log -Step $Module -Status Warning -Message "Runtime value(s) not declared by $Module and ignored: $($ignored -join ', ')"
    }

    $script:CurrentStep = $Module
    $deploymentName = "avdlab-$Module-$($script:RunId)"
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Write-Log -Step $Module -Status Start -Message $Description -Data @{
        module         = $Module
        deploymentName = $deploymentName
        parameters     = ($splat.Keys | Sort-Object) -join ', '
    }

    $deployParams = @{
        ResourceGroupName       = $ResourceGroupName
        Name                    = $deploymentName
        TemplateFile            = $modulePath
        TemplateParameterObject = $splat
        ErrorAction             = 'Stop'
    }

    if ($Validate) {
        # what-if, not Test-AzResourceGroupDeployment: what-if reports the actual
        # predicted resource changes rather than only validating the template.
        $whatIf = Get-AzResourceGroupDeploymentWhatIfResult @deployParams
        $stopwatch.Stop()

        $changes = @($whatIf.Changes | Where-Object { $_.ChangeType -ne 'NoChange' -and $_.ChangeType -ne 'Ignore' })
        foreach ($change in $changes) {
            Write-Log -Step $Module -Status Info -Message ("{0,-8} {1}" -f $change.ChangeType, $change.RelativeResourceId)
        }
        Write-Log -Step $Module -Status Success -Message "$Description - what-if: $($changes.Count) change(s) predicted" `
            -DurationSeconds $stopwatch.Elapsed.TotalSeconds -Data @{ changeCount = $changes.Count }
        return @{}
    }

    $deployment = New-AzResourceGroupDeployment @deployParams
    $stopwatch.Stop()

    if ($deployment.ProvisioningState -ne 'Succeeded') {
        throw "Deployment '$deploymentName' finished in state '$($deployment.ProvisioningState)'."
    }

    # Unwrap outputs to a plain hashtable. Secure outputs come back with a null
    # Value on the deployment object, so they are read separately where needed.
    $outputs = @{}
    if ($deployment.Outputs) {
        foreach ($key in $deployment.Outputs.Keys) {
            $outputs[$key] = $deployment.Outputs[$key].Value
        }
    }

    $loggable = @{}
    foreach ($key in $outputs.Keys) {
        $loggable[$key] = if ($outputs[$key] -is [array]) { $outputs[$key] -join ', ' } else { "$($outputs[$key])" }
    }

    Write-Log -Step $Module -Status Success -Message $Description -DurationSeconds $stopwatch.Elapsed.TotalSeconds -Data @{
        module         = $Module
        deploymentName = $deploymentName
        outputs        = $loggable
    }

    $script:Outputs[$Module] = $loggable
    return $outputs
}

function Invoke-LabScript {
    <#
        Runs a sibling script as a child process and folds the result into the
        transcript. Child scripts stay standalone-runnable with their own plain
        console output; the orchestrator is what turns that into a structured
        record. That is why there is no shared logging module to install.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Script,
        [Parameter(Mandatory)][string]$Description,
        [hashtable]$Arguments = @{},
        [switch]$ContinueOnError
    )

    $scriptPath = Join-Path $PSScriptRoot $Script
    if (-not (Test-Path $scriptPath)) { throw "Script not found: $scriptPath" }

    $script:CurrentStep = $Script
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Log -Step $Script -Status Start -Message $Description

    try {
        & $scriptPath @Arguments
        $stopwatch.Stop()
        Write-Log -Step $Script -Status Success -Message $Description -DurationSeconds $stopwatch.Elapsed.TotalSeconds
    }
    catch {
        $stopwatch.Stop()
        if (-not $ContinueOnError) { throw }
        Write-Log -Step $Script -Status Warning -Message "$Description - continuing despite: $($_.Exception.Message)" `
            -DurationSeconds $stopwatch.Elapsed.TotalSeconds
    }
}

function New-LabAdminPassword {
    <#
        Random, generated per run, never written anywhere, discarded when the
        process exits. Entra ID join means nothing depends on it afterwards -- it
        exists only because ARM requires an adminPassword to provision a Windows VM.

        RandomNumberGenerator rather than Get-Random: Get-Random is seeded
        pseudo-randomness and is not intended for anything security-relevant.
    #>
    $sets = @(
        'ABCDEFGHJKLMNPQRSTUVWXYZ'
        'abcdefghijkmnpqrstuvwxyz'
        '23456789'
        '!@#$%^&*()-_=+'
    )

    $chars = [System.Collections.Generic.List[char]]::new()
    # One from each set first, so the result always satisfies Windows complexity
    # rules rather than satisfying them with high probability.
    foreach ($set in $sets) {
        $chars.Add($set[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($set.Length)])
    }
    $all = -join $sets
    while ($chars.Count -lt 24) {
        $chars.Add($all[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($all.Length)])
    }

    # Fisher-Yates, so the guaranteed characters are not always in positions 1-4.
    for ($i = $chars.Count - 1; $i -gt 0; $i--) {
        $j = [System.Security.Cryptography.RandomNumberGenerator]::GetInt32($i + 1)
        ($chars[$i], $chars[$j]) = ($chars[$j], $chars[$i])
    }

    return (ConvertTo-SecureString -String (-join $chars) -AsPlainText -Force)
}

function Get-HostPoolRegistrationToken {
    <#
        The token is a @secure() output, and ARM does not return secure outputs on
        a later GET of the deployment. It is usually present on the object the
        deployment cmdlet just returned; when it is not, ask the host pool
        directly via its retrieveRegistrationToken action.

        REST rather than Get-AzWvdHostPoolRegistrationToken on purpose: that cmdlet
        lives in Az.DesktopVirtualization, and requiring a whole extra module for
        one call is a poor trade when the action is a single POST.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$DeploymentOutputs,
        [Parameter(Mandatory)][string]$HostPoolName
    )

    if ($DeploymentOutputs.ContainsKey('registrationToken') -and $DeploymentOutputs['registrationToken']) {
        return $DeploymentOutputs['registrationToken']
    }

    Write-Log -Step 'hostpool' -Status Info -Message 'Registration token not returned in deployment outputs; retrieving from the host pool directly'

    $subscriptionId = (Get-AzContext).Subscription.Id
    $path = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName" +
            "/providers/Microsoft.DesktopVirtualization/hostPools/$HostPoolName" +
            '/retrieveRegistrationToken?api-version=2024-04-03'

    $response = Invoke-AzRestMethod -Path $path -Method POST
    if ($response.StatusCode -ge 400) {
        throw "Could not retrieve the host pool registration token (HTTP $($response.StatusCode)): $($response.Content)"
    }

    $token = ($response.Content | ConvertFrom-Json).token
    if (-not $token) {
        throw 'The host pool returned an empty registration token. Re-deploy hostpool.bicep to mint a new one.'
    }
    return $token
}

function Connect-AvdLabContext {
    <#
        Connect, confirm we are pointed at the intended subscription and tenant,
        and run the subscription pre-flight checks. Checks and reports only --
        never remediates. Initialize-AvdLabPrerequisites.ps1 is the script that
        changes things, and it is run once by choice.

        "Setup once, verify every time."
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Config)

    Write-Phase 'Phase 1 of 12 - Context and pre-flight'

    $azure = $Config['azure']
    $subscriptionId = $azure['subscriptionId']
    $tenantId = $azure['tenantId']

    if ($subscriptionId -like '<*>' -or $tenantId -like '<*>') {
        throw @"
The configuration file still holds placeholders:
    subscriptionId = $subscriptionId
    tenantId       = $tenantId

Copy orchestrator.config.json to orchestrator.local.config.json and put your real
values there. The local file is gitignored; the tracked one must keep placeholders.
"@
    }

    $context = Get-AzContext
    if (-not $context -or $context.Subscription.Id -ne $subscriptionId -or $context.Tenant.Id -ne $tenantId) {
        Write-Log -Step 'context' -Status Info -Message "Connecting to subscription $subscriptionId"
        Connect-AzAccount -Subscription $subscriptionId -Tenant $tenantId | Out-Null
        $context = Get-AzContext
    }

    # Belt and braces. Connect-AzAccount can succeed against a different
    # subscription than the one asked for if the account lacks access to it, and
    # deploying a lab into the wrong subscription is a bad way to find that out.
    if ($context.Subscription.Id -ne $subscriptionId) {
        throw "Connected to subscription $($context.Subscription.Id) but the config asks for $subscriptionId."
    }
    if ($context.Tenant.Id -ne $tenantId) {
        throw "Connected to tenant $($context.Tenant.Id) but the config asks for $tenantId."
    }

    Write-Log -Step 'context' -Status Success -Message "Connected to '$($context.Subscription.Name)' as $($context.Account.Id)" -Data @{
        subscriptionId = $subscriptionId
        tenantId       = $tenantId
    }

    Test-LabPreflight
}

function Test-LabPreflight {
    <#
        Checks, ordered by how far into a deployment the corresponding failure
        would otherwise surface. The point of every one of them is to fail in
        phase 1 rather than phase 8.

        Leftover placeholders and a taken storage account name are the two that
        motivated this: both are trivially detectable up front, and both
        otherwise fail only after several minutes of real resources being
        created -- a storage account name collision kills phase 3, and a
        placeholder budget email kills phase 8, by which point session hosts are
        already provisioned and billing.
    #>
    [CmdletBinding()]
    param()

    # --- Leftover placeholders ---
    # The tracked parameter file ships placeholders by design, so a user who
    # copied it and only half-filled the copy is the expected case, not an edge
    # one. Catch every <ANGLE_BRACKET> value at once rather than one per failed run.
    $placeholders = @()
    foreach ($name in ($script:LabParameters.Keys | Sort-Object)) {
        $value = $script:LabParameters[$name]
        # -cmatch, not -match: PowerShell's -match is case-insensitive, so [A-Z_]
        # would also match a lowercase value that happens to be angle-wrapped.
        # Placeholders are UPPERCASE by convention, and that is the whole signal.
        if ($value -is [string] -and $value -cmatch '^<[A-Z_]+>$') { $placeholders += "$name = $value" }
    }
    if ($placeholders) {
        throw @"
The parameter file still holds placeholder value(s):

    $($placeholders -join "`n    ")

Fill these in in bicep/parameters/avdlab.local.bicepparam (gitignored). The
tracked avdlab.bicepparam must keep its placeholders.
"@
    }
    Write-Log -Step 'preflight' -Status Success -Message 'No placeholder values left in the parameter file'

    # --- Lab name ---
    Assert-LabName -LabName $script:LabName
    Write-Log -Step 'preflight' -Status Success -Message "Lab name '$($script:LabName)' is valid; resources will be named *-avdlab-$($script:LabName)"

    # --- Resource providers ---
    $required = @('Microsoft.DesktopVirtualization', 'Microsoft.Compute', 'Microsoft.Network', 'Microsoft.Storage', 'Microsoft.OperationalInsights', 'Microsoft.Insights')
    $unregistered = @()
    foreach ($provider in $required) {
        $state = (Get-AzResourceProvider -ProviderNamespace $provider -ErrorAction SilentlyContinue |
            Select-Object -First 1).RegistrationState
        if ($state -ne 'Registered') { $unregistered += "$provider ($state)" }
    }
    if ($unregistered) {
        throw @"
Resource provider(s) not registered: $($unregistered -join ', ')

Run Initialize-AvdLabPrerequisites.ps1 first -- it registers these for you. This
script reports and stops by design; it does not change your subscription.
"@
    }
    Write-Log -Step 'preflight' -Status Success -Message "All $($required.Count) required resource providers registered"

    # --- vCPU quota ---
    $vmSize = $script:LabParameters['vmSize']
    $hostCount = $script:LabParameters['sessionHostCount']
    $location = $script:DeployLocation

    try {
        # REST rather than Get-AzVMUsage: that cmdlet lives in Az.Compute, and the
        # tooling list deliberately stops at Az.Accounts/Az.Resources/Az.Storage.
        # One usages call is not worth a fourth module on the prerequisite list.
        $subscriptionId = (Get-AzContext).Subscription.Id
        $response = Invoke-AzRestMethod -Method GET -Path (
            "/subscriptions/$subscriptionId/providers/Microsoft.Compute/locations/$location/usages" +
            '?api-version=2023-07-01')
        if ($response.StatusCode -ge 400) { throw "HTTP $($response.StatusCode)" }

        $usage = ($response.Content | ConvertFrom-Json).value |
            Where-Object { $_.name.value -eq 'cores' } | Select-Object -First 1
        if ($usage) {
            $available = $usage.limit - $usage.currentValue
            # Approximate: the digit in the size name is the vCPU count for the
            # families this lab uses. The precise number comes from the SKUs API,
            # which Initialize-AvdLabPrerequisites.ps1 queries properly. This is a
            # cheap sanity check, not a substitute for that.
            $perHost = if ($vmSize -match '_D(\d+)') { [int]$Matches[1] } else { 4 }
            $needed = $perHost * $hostCount
            if ($available -lt $needed) {
                Write-Log -Step 'preflight' -Status Warning `
                    -Message "Regional vCPU quota may be short: $available free in $location, roughly $needed needed for $hostCount x $vmSize"
            }
            else {
                Write-Log -Step 'preflight' -Status Success -Message "Regional vCPU quota: $available free in $location, roughly $needed needed"
            }
        }
    }
    catch {
        Write-Log -Step 'preflight' -Status Warning -Message "Could not read vCPU quota: $($_.Exception.Message)"
    }

    # NOTE: there is no storage account name check here any more. The name is
    # derived from the lab name plus uniqueString(resourceGroup().id), so it
    # cannot collide with another tenant's and cannot be mistyped. The check
    # this replaced existed only because the name used to be hand-entered.

    # --- Inherited Azure Policy ---
    # The check most likely to matter in a subscription that already has other
    # workloads in it, and the one whose failure message is least helpful when it
    # does bite. Surfacing the assignments up front turns "deployment failed at
    # phase 4" into "the mandatory-tags policy is going to reject this".
    try {
        $assignments = @(Get-AzPolicyAssignment -ErrorAction Stop)
        if ($assignments.Count -gt 0) {
            Write-Log -Step 'preflight' -Status Warning `
                -Message "$($assignments.Count) Azure Policy assignment(s) in scope. Mandatory tags, allowed regions/SKUs, or required NSG rules can reject a deployment partway through." `
                -Data @{ policies = ($assignments | ForEach-Object { $_.Name }) -join ', ' }
        }
        else {
            Write-Log -Step 'preflight' -Status Success -Message 'No Azure Policy assignments in scope'
        }
    }
    catch {
        Write-Log -Step 'preflight' -Status Warning -Message "Could not enumerate Azure Policy assignments: $($_.Exception.Message)"
    }
}

# ===========================================================================
# Main sequence
# ===========================================================================

Write-Host ''
Write-Host 'AVD Lab Kit - deployment' -ForegroundColor Cyan
if ($Validate) {
    Write-Host 'VALIDATE MODE - what-if only. Nothing will be created or changed.' -ForegroundColor Yellow
}
Write-Host ''

$configFile = Resolve-LabFile -Explicit $ConfigPath `
    -LocalPath (Join-Path $RepoRoot 'orchestrator.local.config.json') `
    -TrackedPath (Join-Path $RepoRoot 'orchestrator.config.json')

$parameterFile = Resolve-LabFile -Explicit $ParameterFile `
    -LocalPath (Join-Path $RepoRoot 'bicep/parameters/avdlab.local.bicepparam') `
    -TrackedPath (Join-Path $RepoRoot 'bicep/parameters/avdlab.bicepparam')

# ConvertFrom-Json -AsHashtable: the config is data, and a hashtable indexes
# cleanly under StrictMode where a PSCustomObject throws on a missing member.
$config = Get-Content $configFile -Raw | ConvertFrom-Json -AsHashtable

$script:BicepCommand = Get-BicepCommand
$script:LabParameters = Get-LabParameters -Path $parameterFile
$script:DeployLocation = if ($Location) { $Location } elseif ($LabParameters.ContainsKey('location')) { $LabParameters['location'] } else { 'eastus2' }
$script:LabName = if ($LabParameters.ContainsKey('labName')) { $LabParameters['labName'] } else { 'lab' }

# Derived once, used everywhere below. These mirror the Bicep modules exactly.
$script:HostPoolName = Get-LabResourceName -Kind hostPool -LabName $script:LabName
$script:AppGroupName = Get-LabResourceName -Kind appGroup -LabName $script:LabName
$script:WorkspaceName = Get-LabResourceName -Kind workspace -LabName $script:LabName

if ($config.ContainsKey('narration')) {
    $script:NarrationEnabled = [bool]$config['narration']['enabled']
    $script:StepDelaySeconds = [int]$config['narration']['stepDelaySeconds']
}

$reportRoot = if ($ReportPath) { $ReportPath }
              elseif ($config.ContainsKey('report')) { $config['report']['outputPath'] }
              else { './reports' }
$script:RunDirectory = Join-Path $RepoRoot (Join-Path $reportRoot $script:RunId)
New-Item -ItemType Directory -Path $script:RunDirectory -Force | Out-Null
$script:LogFile = Join-Path $script:RunDirectory 'deployment-log.jsonl'

Write-Log -Step 'startup' -Status Info -Message "Config:     $(Split-Path -Leaf $configFile)"
Write-Log -Step 'startup' -Status Info -Message "Parameters: $(Split-Path -Leaf $parameterFile)"
Write-Log -Step 'startup' -Status Info -Message "Transcript: $($script:LogFile)"

# The cost guardrail must not be able to deploy as a comfortable no-op. A
# guardrail you believe in but that does not exist is worse than no guardrail.
if ($LabParameters.ContainsKey('costGuardrailMode') -and $LabParameters['costGuardrailMode'] -eq 'AlertAndDelete') {
    throw @'
costGuardrailMode is set to 'AlertAndDelete', which is designed but not built.

Only 'AlertOnly' is implemented. AlertAndDelete would need an Automation Account,
a teardown runbook, and a second higher budget threshold to trigger it -- none of
which this deploys. Rather than let you believe an automatic teardown exists when
it does not, this stops here. Set costGuardrailMode to 'AlertOnly'.
'@
}

$exitCode = 0

try {
    # ---- 1. Context and pre-flight ----
    Connect-AvdLabContext -Config $config

    if (-not $Validate) {
        $existing = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-AzResourceGroup -Name $ResourceGroupName -Location $script:DeployLocation -Tag $LabParameters['tags'] | Out-Null
            Write-Log -Step 'resourcegroup' -Status Success -Message "Created resource group $ResourceGroupName in $($script:DeployLocation)"
        }
        else {
            Write-Log -Step 'resourcegroup' -Status Info -Message "Using existing resource group $ResourceGroupName"
        }
    }

    # ---- 2. Network ----
    Write-Phase 'Phase 2 of 12 - Networking'
    $network = Invoke-LabDeployment -Module 'network' -Description 'Deploying VNet, subnet, NSG and NAT gateway'

    # ---- 3. Storage ----
    Write-Phase 'Phase 3 of 12 - FSLogix storage'
    $storage = Invoke-LabDeployment -Module 'storage' -Description 'Deploying Azure Files share with Microsoft Entra Kerberos enabled'

    # ---- 4. Entra Kerberos app registration ----
    Write-Phase 'Phase 4 of 12 - Microsoft Entra Kerberos'
    if ($SkipFSLogix) {
        Write-Log -Step 'Set-AvdLabFSLogixAuth.ps1' -Status Skipped `
            -Message '-SkipFSLogix set: profiles will be local and non-roaming'
    }
    elseif ($Validate) {
        Write-Log -Step 'Set-AvdLabFSLogixAuth.ps1' -Status Skipped `
            -Message 'Validate mode: Graph changes are not simulated. Run the script with -WhatIf to rehearse this step.'
    }
    else {
        Invoke-LabScript -Script 'Set-AvdLabFSLogixAuth.ps1' `
            -Description 'Configuring the storage account app registration (consent, cloud group SIDs tag, MFA check)' `
            -Arguments @{
                StorageAccountName = $storage['storageAccountName']
                TenantId           = $config['azure']['tenantId']
            }
    }

    # ---- 5. Host pool ----
    Write-Phase 'Phase 5 of 12 - Host pool'
    $hostPool = Invoke-LabDeployment -Module 'hostpool' -Description 'Deploying the pooled host pool and minting a registration token'

    # ---- 6. App group, then workspace ----
    Write-Phase 'Phase 6 of 12 - Application group and workspace'
    $appGroup = Invoke-LabDeployment -Module 'appgroup' -Description 'Deploying the desktop application group' -Runtime @{
        hostPoolId = if ($Validate) { '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/validate/providers/Microsoft.DesktopVirtualization/hostPools/validate' } else { $hostPool['hostPoolId'] }
    }

    Invoke-LabDeployment -Module 'workspace' -Description 'Deploying the workspace and publishing the application group' -Runtime @{
        applicationGroupIds = if ($Validate) { @() } else { @($appGroup['appGroupId']) }
    } | Out-Null

    # ---- 7. Session hosts ----
    Write-Phase 'Phase 7 of 12 - Session hosts'
    $sessionHostRuntime = @{
        subnetId          = if ($Validate) { '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/validate/providers/Microsoft.Network/virtualNetworks/validate/subnets/validate' } else { $network['subnetId'] }
        adminPassword     = New-LabAdminPassword
        registrationToken = if ($Validate) { (ConvertTo-SecureString 'validate-only' -AsPlainText -Force) } else {
            (ConvertTo-SecureString (Get-HostPoolRegistrationToken -DeploymentOutputs $hostPool -HostPoolName $script:HostPoolName) -AsPlainText -Force)
        }
        enableFsLogix     = (-not $SkipFSLogix)
        profileShareUncPath = if ($Validate -or $SkipFSLogix) { '' } else { $storage['profileShareUncPath'] }
    }

    $hostCount = $LabParameters['sessionHostCount']
    Write-Log -Step 'sessionhosts' -Status Info -Message "Registering $hostCount session host(s) to $($script:HostPoolName)"
    $sessionHosts = Invoke-LabDeployment -Module 'sessionhosts' -Description "Deploying $hostCount Entra-joined session host(s)" -Runtime $sessionHostRuntime

    # ---- 8. Monitoring ----
    Write-Phase 'Phase 8 of 12 - Monitoring and cost guardrail'
    Invoke-LabDeployment -Module 'monitoring' -Description 'Deploying Log Analytics, AVD diagnostics, data collection rule and budget alert' -Runtime @{
        sessionHostNames = if ($Validate) { @() } else { @($sessionHosts['sessionHostNames']) }
    } | Out-Null

    # ---- 9. Scaling plan ----
    Write-Phase 'Phase 9 of 12 - Autoscale'
    $scalingRuntime = @{
        hostPoolId = if ($Validate) { '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/validate/providers/Microsoft.DesktopVirtualization/hostPools/validate' } else { $hostPool['hostPoolId'] }
    }
    # Schedule times live in the orchestrator config so they can be changed
    # without editing Bicep.
    if ($config.ContainsKey('scalingPlanSchedule')) {
        $schedule = $config['scalingPlanSchedule']
        foreach ($key in @('timeZone', 'daysOfWeek', 'rampUpStartTime', 'peakStartTime', 'rampDownStartTime', 'offPeakStartTime')) {
            if ($schedule.ContainsKey($key)) { $scalingRuntime[$key] = $schedule[$key] }
        }
    }
    Invoke-LabDeployment -Module 'scalingplan' -Description 'Deploying the weekday autoscale schedule' -Runtime $scalingRuntime | Out-Null

    # ---- 10. Assignments ----
    Write-Phase 'Phase 10 of 12 - Access assignments'
    if ($Validate) {
        Write-Log -Step 'Add-AvdLabAssignments.ps1' -Status Skipped -Message 'Validate mode: role assignments are not simulated.'
    }
    else {
        Invoke-LabScript -Script 'Add-AvdLabAssignments.ps1' `
            -Description 'Granting the demo group desktop access, share access, and the AVD service principal power-management rights' `
            -Arguments @{
                ResourceGroupName  = $ResourceGroupName
                AppGroupName       = $script:AppGroupName
                # From the deployment output, not derived: the storage account
                # name is built with uniqueString(), which has no PowerShell
                # equivalent. This is the only name the orchestrator cannot
                # work out for itself.
                StorageAccountName = $storage['storageAccountName']
                DemoGroupObjectId  = $config['assignment']['demoGroupObjectId']
            }
    }

    # ---- 11. Smoke test ----
    Write-Phase 'Phase 11 of 12 - Smoke test'
    if ($Validate) {
        Write-Log -Step 'Test-AvdLabDeployment.ps1' -Status Skipped -Message 'Validate mode: nothing was deployed to test.'
    }
    else {
        # ContinueOnError: a failed check is information, not a reason to skip the
        # as-built report. The report is most valuable precisely when something is
        # not right.
        Invoke-LabScript -Script 'Test-AvdLabDeployment.ps1' -ContinueOnError `
            -Description 'Verifying the deployed environment' `
            -Arguments @{
                ResourceGroupName  = $ResourceGroupName
                HostPoolName       = $script:HostPoolName
                StorageAccountName = $storage['storageAccountName']
                ExpectedHostCount  = $LabParameters['sessionHostCount']
            }
    }

    # ---- 12. As-built report ----
    Write-Phase 'Phase 12 of 12 - As-built report'
    if ($Validate) {
        Write-Log -Step 'New-AvdLabReport.ps1' -Status Skipped -Message 'Validate mode: nothing was built to document.'
    }
    else {
        Invoke-LabScript -Script 'New-AvdLabReport.ps1' -ContinueOnError `
            -Description 'Generating the as-built document' `
            -Arguments @{
                Mode              = 'AsBuilt'
                ResourceGroupName = $ResourceGroupName
                TranscriptPath    = $script:LogFile
                OutputPath        = $script:RunDirectory
            }
    }
}
catch {
    $exitCode = 1
    Write-Log -Step $script:CurrentStep -Status Failure -Message $_.Exception.Message -Data @{
        step       = $script:CurrentStep
        exception  = $_.Exception.GetType().FullName
        scriptLine = "$($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)"
    }

    Write-Host ''
    Write-Host "DEPLOYMENT FAILED at step '$($script:CurrentStep)'." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''

    # Evidence bundle instead of the as-built report. Best effort: a report
    # generator that throws while reporting a failure helps nobody.
    try {
        & (Join-Path $PSScriptRoot 'New-AvdLabReport.ps1') `
            -Mode Evidence `
            -ResourceGroupName $ResourceGroupName `
            -TranscriptPath $script:LogFile `
            -OutputPath $script:RunDirectory `
            -FailedStep $script:CurrentStep
    }
    catch {
        Write-Host "Could not generate the evidence bundle: $($_.Exception.Message)" -ForegroundColor DarkYellow
        Write-Host "The raw transcript is still at $($script:LogFile)" -ForegroundColor DarkYellow
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
$elapsed = (Get-Date).ToUniversalTime() - $script:StartedUtc

Write-Host ''
Write-Host ('-' * 74) -ForegroundColor DarkGray
if ($exitCode -eq 0) {
    if ($Validate) {
        Write-Host "VALIDATION COMPLETE in $([int]$elapsed.TotalSeconds)s. Nothing was changed." -ForegroundColor Green
    }
    else {
        Write-Host "DEPLOYMENT COMPLETE in $([int]$elapsed.TotalMinutes)m $($elapsed.Seconds)s." -ForegroundColor Green
        Write-Host ''
        Write-Host "  Resource group   $ResourceGroupName" -ForegroundColor Gray
        Write-Host "  Lab name         $($script:LabName)" -ForegroundColor Gray
        Write-Host "  Host pool        $($script:HostPoolName)" -ForegroundColor Gray
        Write-Host "  Workspace        $($script:WorkspaceName)" -ForegroundColor Gray
        Write-Host "  Application grp  $($script:AppGroupName)" -ForegroundColor Gray
        Write-Host "  Session hosts    $($LabParameters['sessionHostCount'])" -ForegroundColor Gray
        if (-not $SkipFSLogix -and $storage -and $storage.ContainsKey('profileShareUncPath')) {
            Write-Host "  FSLogix share    $($storage['profileShareUncPath'])" -ForegroundColor Gray
        }
        elseif (-not $SkipFSLogix -and $storage -and $storage.ContainsKey('storageAccountName')) {
            Write-Host "  FSLogix share    $($storage['storageAccountName']) / $($LabParameters['shareName'])" -ForegroundColor Gray
        }
        else {
            Write-Host '  FSLogix          disabled (-SkipFSLogix); profiles are local' -ForegroundColor Yellow
        }
        Write-Host ''
        Write-Host '  Users subscribe at   https://client.wvd.microsoft.com/arm/webclient' -ForegroundColor Gray
        Write-Host "  As-built report      $script:RunDirectory" -ForegroundColor Gray
        Write-Host ''
        Write-Host "  Tear it down with:   ./scripts/Remove-AvdLab.ps1 -ResourceGroupName $ResourceGroupName" -ForegroundColor Gray
    }
}
else {
    Write-Host "DEPLOYMENT FAILED. Evidence bundle: $script:RunDirectory" -ForegroundColor Red
}
Write-Host ('-' * 74) -ForegroundColor DarkGray
Write-Host ''

exit $exitCode
