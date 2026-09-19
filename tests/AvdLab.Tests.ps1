#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    AVD Lab Kit — Pester suite.

    Three concerns live here:

      1. Leak prevention. Tracked files must never carry a real subscription,
         tenant or object ID, a real email address, or a hardcoded password.
         These run on every commit and are the reason the tracked parameter files
         can stay placeholder-only forever.

      2. Parameter validation. avdlab.bicepparam uses `using none`, so Bicep does
         not type-check its values against any module. These tests are what was
         traded for that. If they are ever deleted, a typo'd parameter name
         becomes a silently ignored value rather than a build failure.

      3. Repository shape. Every deliverable exists, every script parses, and the
         naming convention holds.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:ModuleDir = Join-Path $RepoRoot 'bicep/modules'
    $script:ParamDir = Join-Path $RepoRoot 'bicep/parameters'
    $script:ScriptDir = Join-Path $RepoRoot 'scripts'
}

Describe 'Repository structure' {
    It "has the '<_>' directory" -ForEach @(
        'bicep/modules'
        'bicep/parameters'
        'scripts'
        'tests'
        '.github/workflows'
    ) {
        Join-Path $RepoRoot $_ | Should -Exist
    }

    It "ships the '<_>' Bicep module" -ForEach @(
        'network', 'storage', 'hostpool', 'appgroup'
        'workspace', 'sessionhosts', 'monitoring', 'scalingplan'
    ) {
        Join-Path $ModuleDir "$_.bicep" | Should -Exist
    }

    It "ships the '<_>' script" -ForEach @(
        'Deploy-AvdLab.ps1'
        'Remove-AvdLab.ps1'
        'Initialize-AvdLabPrerequisites.ps1'
        'Set-AvdLabFSLogixAuth.ps1'
        'Add-AvdLabAssignments.ps1'
        'Test-AvdLabDeployment.ps1'
        'New-AvdLabReport.ps1'
    ) {
        Join-Path $ScriptDir $_ | Should -Exist
    }

    It 'ships an MIT LICENSE' {
        $license = Join-Path $RepoRoot 'LICENSE'
        $license | Should -Exist
        Get-Content $license -Raw | Should -Match 'MIT License'
    }
}

Describe 'Leak prevention' {

    Context '.gitignore' {
        BeforeAll {
            $script:GitIgnore = Get-Content (Join-Path $RepoRoot '.gitignore') -Raw
        }

        # These two patterns are the whole contract: real values live in local
        # override files, and those files must be unstageable by construction.
        It "ignores the '<_>' local-override pattern" -ForEach @(
            '*.local.bicepparam'
            '*.local.config.json'
        ) {
            $GitIgnore | Should -BeLike "*$_*"
        }
    }

    Context 'Tracked files carry placeholders, never real values' {
        BeforeAll {
            # Only inspect files git actually tracks. An untracked local override
            # sitting in the working tree is fine and expected.
            Push-Location $RepoRoot
            $tracked = @(git ls-files -- '*.bicepparam' '*.config.json' '*.bicep')
            Pop-Location

            $script:TrackedConfig = $tracked | Where-Object { $_ } | ForEach-Object {
                [pscustomobject]@{
                    Path    = $_
                    Content = Get-Content (Join-Path $RepoRoot $_) -Raw -ErrorAction SilentlyContinue
                }
            }
        }

        It 'contains no bare GUID that could be a real subscription/tenant/object ID' {
            # A placeholder like <YOUR_SUBSCRIPTION_ID> has no GUID shape, so any
            # match here is a real-looking value that should not be tracked.
            $guid = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

            $offenders = $TrackedConfig |
                Where-Object { $_.Content -match $guid } |
                ForEach-Object { $_.Path }

            $offenders | Should -BeNullOrEmpty -Because 'real IDs belong only in gitignored *.local.* overrides'
        }

        It 'contains no real email address in budgetAlertEmail' {
            $offenders = $TrackedConfig |
                Where-Object { $_.Content -match "budgetAlertEmail\s*=\s*'[^<][^']*@" } |
                ForEach-Object { $_.Path }

            $offenders | Should -BeNullOrEmpty -Because 'the tracked param file must keep the <YOUR_EMAIL> placeholder'
        }

        It 'hardcodes no local admin password' {
            $offenders = $TrackedConfig |
                Where-Object { $_.Content -match "(?i)(adminPassword|localAdminPassword)\s*[:=]\s*'[^']+'" } |
                ForEach-Object { $_.Path }

            $offenders | Should -BeNullOrEmpty -Because 'the orchestrator generates a random password at runtime and discards it'
        }
    }

    Context 'Scripts' {
        BeforeAll {
            Push-Location $RepoRoot
            $script:TrackedScripts = @(git ls-files -- '*.ps1') | Where-Object { $_ } | ForEach-Object {
                [pscustomobject]@{ Path = $_; Content = Get-Content (Join-Path $RepoRoot $_) -Raw }
            }
            Pop-Location
        }

        It 'contains no bare GUID outside the documented well-known service principal IDs' {
            # Well-known Microsoft appIds are identical in every tenant, so they
            # are not secrets and must be allowed. Anything else is suspect.
            $wellKnown = @(
                '62e90394-69f5-4237-9190-012177145e10'  # Global Administrator role template
                '00000003-0000-0000-c000-000000000000'  # Microsoft Graph
                '9cdead84-a844-4324-93f2-b2e6bb768d07'  # Azure Virtual Desktop
                '00000000-0000-0000-0000-000000000000'  # all-zero placeholder
            )
            $guid = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

            $offenders = foreach ($file in $TrackedScripts) {
                $found = [regex]::Matches($file.Content, $guid) | ForEach-Object { $_.Value.ToLower() }
                $unexpected = $found | Where-Object { $_ -notin $wellKnown }
                if ($unexpected) { "$($file.Path): $($unexpected -join ', ')" }
            }

            $offenders | Should -BeNullOrEmpty -Because 'a real directory object ID must never be tracked'
        }

        It "parses as valid PowerShell: '<_.Path>'" -ForEach @(
            (Get-ChildItem (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts') -Filter '*.ps1' -File |
                ForEach-Object { @{ Path = $_.Name; Full = $_.FullName } })
        ) {
            $parseErrors = $null
            $tokens = $null
            [System.Management.Automation.Language.Parser]::ParseFile($_.Full, [ref]$tokens, [ref]$parseErrors) | Out-Null
            $parseErrors | Should -BeNullOrEmpty
        }
    }
}

Describe 'Parameter file (avdlab.bicepparam)' {
    <#
        These tests are the compile-time safety `using none` gives up. They are
        not optional extras.
    #>

    BeforeAll {
        $script:ParamFile = Join-Path $ParamDir 'avdlab.bicepparam'

        # Supplied by the orchestrator at deployment time, so they must NOT appear
        # in the tracked file: module outputs, generated secrets, time-derived
        # values, and anything computed from a switch.
        $script:RuntimeInjected = @(
            'hostPoolId'            # output of hostpool.bicep
            'subnetId'              # output of network.bicep
            'applicationGroupIds'   # output of appgroup.bicep
            'sessionHostNames'      # output of sessionhosts.bicep
            'profileShareUncPath'   # output of storage.bicep
            'registrationToken'     # output of hostpool.bicep (secret)
            'adminPassword'         # generated at runtime, never stored
            'tokenExpirationTime'   # dateTimeAdd(utcNow(), ...) default
            'budgetStartDate'       # utcNow('yyyy-MM-01') default
            'enableFsLogix'         # set from the orchestrator's -SkipFSLogix switch
        )

        # Names declared by more than one module that genuinely mean the SAME
        # thing everywhere they appear, and are therefore safe to assign once in
        # a flat file. Every other repeated name is ambiguous by definition.
        #
        # Adding a name here is a claim that you checked. `friendlyName` is the
        # standing counter-example: four modules, four different meanings.
        $script:SharedParams = @(
            'location'          # every module
            'tags'              # every module
            'hostPoolName'      # hostpool, sessionhosts, monitoring
            'appGroupName'      # appgroup, monitoring
            'workspaceName'     # workspace, monitoring
        )

        # name -> list of modules declaring it, and which are required (no default).
        $script:Declared = @{}
        $script:Required = @{}
        Get-ChildItem $ModuleDir -Filter '*.bicep' -File | ForEach-Object {
            $module = $_.BaseName
            foreach ($line in Get-Content $_.FullName) {
                if ($line -match '^param\s+(\w+)\s+[\w\[\]]+\s*$') {
                    $name = $Matches[1]
                    if (-not $Required.ContainsKey($name)) { $Required[$name] = @() }
                    $Required[$name] += $module
                }
                if ($line -match '^param\s+(\w+)\s') {
                    $name = $Matches[1]
                    if (-not $Declared.ContainsKey($name)) { $Declared[$name] = @() }
                    $Declared[$name] += $module
                }
            }
        }

        # Assigned parameter names, taken from the compiled output rather than
        # regexed out of the source -- if it doesn't compile, nothing else matters.
        #
        # Either Bicep CLI will do. CI installs the az wrapper; a contributor is
        # just as likely to have the standalone binary, and a test suite that only
        # runs on the CI runner is a test suite nobody runs before pushing.
        $compiled = if (Get-Command bicep -ErrorAction SilentlyContinue) {
            bicep build-params $ParamFile --stdout 2>$null | ConvertFrom-Json
        }
        elseif (Get-Command az -ErrorAction SilentlyContinue) {
            az bicep build-params --file $ParamFile --stdout 2>$null | ConvertFrom-Json
        }
        else { $null }
        $script:Assigned = if ($compiled) {
            ($compiled.parametersJson | ConvertFrom-Json).parameters.PSObject.Properties.Name
        }
        else { @() }
    }

    It 'compiles with the Bicep CLI' {
        $ParamFile | Should -Exist
        $Assigned.Count | Should -BeGreaterThan 0 -Because 'a param file that does not compile emits nothing'
    }

    It 'declares `using none`' {
        Get-Content $ParamFile -Raw | Should -Match '(?m)^using none\s*$'
    }

    It 'assigns no parameter that is unknown to every module' {
        # Anything here is a typo. With `using none` a typo is silently ignored
        # rather than rejected, which is precisely why this test exists.
        $unknown = $Assigned | Where-Object { -not $Declared.ContainsKey($_) }
        $unknown | Should -BeNullOrEmpty
    }

    It 'assigns no ambiguous parameter shared across modules with different meanings' {
        $ambiguous = $Assigned | Where-Object {
            $Declared.ContainsKey($_) -and
            $Declared[$_].Count -gt 1 -and
            $_ -notin $SharedParams
        }

        $ambiguous | Should -BeNullOrEmpty -Because 'a flat file would splat one value into every module declaring the name'
    }

    It 'assigns no parameter the orchestrator injects at runtime' {
        $leaked = $Assigned | Where-Object { $_ -in $RuntimeInjected }
        $leaked | Should -BeNullOrEmpty -Because 'module outputs and generated secrets must never be pinned in a tracked file'
    }

    It "satisfies every required parameter of module '<_>'" -ForEach (
        Get-ChildItem (Join-Path (Split-Path -Parent $PSScriptRoot) 'bicep/modules') -Filter '*.bicep' -File |
            ForEach-Object { $_.BaseName }
    ) {
        $module = $_
        $missing = $Required.Keys |
            Where-Object { $module -in $Required[$_] } |
            Where-Object { $_ -notin $Assigned -and $_ -notin $RuntimeInjected }

        $missing | Should -BeNullOrEmpty -Because "deployment of $module would prompt for these"
    }
}

Describe 'Bicep modules' {
    BeforeDiscovery {
        $moduleDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'bicep/modules'
        $script:Modules = if (Test-Path $moduleDir) {
            Get-ChildItem $moduleDir -Filter '*.bicep' -File
        }
        else { @() }
    }

    Context 'Module <_.Name>' -ForEach $Modules {
        It 'is not empty' {
            Get-Content $_.FullName -Raw | Should -Not -BeNullOrEmpty
        }

        It 'declares no secure parameter with a default value' {
            # A @secure() param with a default is a hardcoded secret waiting to happen.
            $content = Get-Content $_.FullName -Raw
            $content | Should -Not -Match '(?ms)@secure\(\)\s*\r?\nparam\s+\w+\s+string\s*='
        }

        It 'describes every parameter it declares' {
            # An undocumented parameter is one the next person has to guess at.
            #
            # Walking backwards from the `param` line looks simpler and is wrong:
            # decorators stack, so @description is routinely separated from its
            # parameter by a multi-line @allowed([...]) block. Track the most
            # recent description instead, and reset it at every declaration.
            $inMultiline = $false
            $sawDescription = $false
            $undocumented = @()

            foreach ($line in (Get-Content $_.FullName)) {
                $trimmed = $line.Trim()

                # A ''' fence opens or closes a multi-line description body. Prose
                # inside it must not be mistaken for a declaration.
                $fences = ([regex]::Matches($trimmed, "'''")).Count
                if ($fences % 2 -eq 1) { $inMultiline = -not $inMultiline }
                if ($inMultiline) {
                    if ($trimmed -match "^@(sys\.)?description\(") { $sawDescription = $true }
                    continue
                }

                if ($trimmed -match "^@(sys\.)?description\(") { $sawDescription = $true; continue }

                if ($trimmed -match '^param\s+(\w+)') {
                    if (-not $sawDescription) { $undocumented += $Matches[1] }
                    $sawDescription = $false
                    continue
                }

                # Any other declaration ends the current decorator block, so a
                # description above it cannot carry down to a later parameter.
                if ($trimmed -match '^(resource|output|var|func|module|type|targetScope|using)\s') {
                    $sawDescription = $false
                }
            }

            $undocumented | Should -BeNullOrEmpty
        }
    }
}
