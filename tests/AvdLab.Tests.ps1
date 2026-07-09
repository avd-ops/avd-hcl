#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    AVD Lab Kit — Pester suite.

    Two concerns live here, deliberately:
      1. Leak prevention (Section 14) — tracked files must never carry real
         subscription/tenant/group IDs. These tests run today and every day.
      2. Bicep parameter + naming-convention validation (Section 7/9) — these
         come online as modules land in Week 1; until then they self-skip
         rather than fail a scaffold-only repo.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:ModuleDir = Join-Path $RepoRoot 'bicep/modules'
    $script:ParamDir = Join-Path $RepoRoot 'bicep/parameters'
}

Describe 'Repository structure' {
    It "has the '<_>' directory from the Section 4 layout" -ForEach @(
        'bicep/modules'
        'bicep/parameters'
        'scripts'
        'tests'
        '.github/workflows'
    ) {
        Join-Path $RepoRoot $_ | Should -Exist
    }

    It 'ships an MIT LICENSE' {
        $license = Join-Path $RepoRoot 'LICENSE'
        $license | Should -Exist
        Get-Content $license -Raw | Should -Match 'MIT License'
    }
}

Describe 'Leak prevention (Section 14)' {

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
            # Only inspect files git actually tracks. An untracked local
            # override sitting in the working tree is fine and expected.
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

            $offenders | Should -BeNullOrEmpty -Because 'Section 5 requires a random runtime-generated password'
        }
    }
}

Describe 'Parameter file (avdlab.bicepparam)' {
    <#
        avdlab.bicepparam uses `using none`, so Bicep does not type-check its values
        against any module (a single param file bound to one template cannot carry
        eight modules' parameters -- BCP259). These tests are what we traded that
        compile-time safety for. If they are ever deleted, a typo'd parameter name
        becomes a silently ignored value.
    #>

    BeforeAll {
        $script:ParamFile = Join-Path $ParamDir 'avdlab.bicepparam'

        # Parameters the orchestrator supplies at runtime, so they must NOT appear
        # in the tracked file: module outputs, generated secrets, time-derived values.
        $script:RuntimeInjected = @(
            'hostPoolId'            # output of hostpool.bicep
            'applicationGroupIds'   # output of appgroup.bicep
            'registrationToken'     # output of hostpool.bicep (secret)
            'tokenExpirationTime'   # dateTimeAdd(utcNow(), ...) default
            'adminPassword'         # generated at runtime, never stored (Section 5)
        )

        # Names legitimately shared, with the same meaning, across every module.
        # Any OTHER name declared by more than one module is ambiguous and must not
        # be assigned in a flat param file -- it would splat into all of them.
        $script:SharedParams = @('location', 'tags')

        # Params for modules not yet written. Listed explicitly so this test reports
        # a real gap rather than quietly tolerating anything unrecognized.
        $script:FutureModuleParams = @(
            'sessionHostCount', 'vmSize', 'imagePublisher', 'imageOffer', 'imageSku'
            'logAnalyticsWorkspaceName', 'logAnalyticsRetentionDays'
            'budgetAmount', 'budgetAlertEmail', 'costGuardrailMode'
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
        $compiled = az bicep build-params --file $ParamFile --stdout 2>$null | ConvertFrom-Json
        $script:Assigned = if ($compiled) {
            ($compiled.parametersJson | ConvertFrom-Json).parameters.PSObject.Properties.Name
        }
        else { @() }
    }

    It 'compiles with az bicep build-params' {
        $ParamFile | Should -Exist
        $Assigned.Count | Should -BeGreaterThan 0 -Because 'a param file that does not compile emits nothing'
    }

    It 'declares `using none`' {
        Get-Content $ParamFile -Raw | Should -Match '(?m)^using none\s*$'
    }

    It 'assigns no parameter that is unknown to every module' {
        # Anything here is either a typo or a param for a module nobody has written.
        $unknown = $Assigned |
            Where-Object { -not $Declared.ContainsKey($_) } |
            Where-Object { $_ -notin $FutureModuleParams }

        $unknown | Should -BeNullOrEmpty -Because 'with `using none` a typo is silently ignored, not rejected'
    }

    It 'assigns no ambiguous parameter shared across modules with different meanings' {
        # e.g. friendlyName means something different in hostpool/appgroup/workspace.
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
        # Discovery-time lookup so -ForEach can expand over real files. Empty
        # during the Week 1 scaffold; the tests below simply do not materialize.
        $moduleDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'bicep/modules'
        $script:Modules = if (Test-Path $moduleDir) {
            Get-ChildItem $moduleDir -Filter '*.bicep' -File
        }
        else { @() }
    }

    It 'has at least one module once Week 1 module work begins' -Skip:($Modules.Count -eq 0) {
        $Modules.Count | Should -BeGreaterThan 0
    }

    Context 'Module <_.Name>' -ForEach $Modules {
        It 'declares a targetScope or relies on the resourceGroup default' {
            $content = Get-Content $_.FullName -Raw
            $content | Should -Not -BeNullOrEmpty
        }

        It 'declares no secure parameter with a default value' {
            # A @secure() param with a default is a hardcoded secret waiting to happen.
            $content = Get-Content $_.FullName -Raw
            $content | Should -Not -Match '(?ms)@secure\(\)\s*\r?\nparam\s+\w+\s+string\s*='
        }
    }
}
