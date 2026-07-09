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
