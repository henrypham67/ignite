# bootstrap.ps1: the pure functions, dot-sourced with IGNITE_SOURCE_ONLY=1.

Describe 'bootstrap.ps1' {
    BeforeAll {
        $script:Bootstrap = (Resolve-Path (Join-Path $PSScriptRoot '../../bootstrap.ps1')).Path
        $env:IGNITE_SOURCE_ONLY = '1'
        . $Bootstrap
    }

    AfterAll {
        $env:IGNITE_SOURCE_ONLY = $null
    }

    BeforeEach {
        $env:IGNITE_NO_ADMIN = $null
        $env:IGNITE_LOCAL_SOURCE = $null
        $env:IGNITE_REPO = $null
        $env:IGNITE_REF = $null
    }

    Context 'Test-IgniteCanElevate' {
        It 'is true when the user is in the Administrators group (S-1-5-32-544)' {
            Mock Get-IgniteGroupSids { @('S-1-1-0', 'S-1-5-32-544', 'S-1-5-32-545') }
            Test-IgniteCanElevate | Should -BeTrue
        }

        It 'is false without the Administrators SID' {
            Mock Get-IgniteGroupSids { @('S-1-1-0', 'S-1-5-32-545') }
            Test-IgniteCanElevate | Should -BeFalse
        }

        It 'is false when IGNITE_NO_ADMIN=1 even for an administrator' {
            Mock Get-IgniteGroupSids { @('S-1-5-32-544') }
            $env:IGNITE_NO_ADMIN = '1'
            Test-IgniteCanElevate | Should -BeFalse
        }
    }

    Context 'Get-IgniteGroupSids' {
        It 'parses the SID column of whoami /groups' {
            $text = @(
                'GROUP INFORMATION'
                '-----------------'
                ''
                'Group Name                             Type             SID          Attributes'
                '====================================== ================ ============ =================================================='
                'Everyone                               Well-known group S-1-1-0      Mandatory group, Enabled by default, Enabled group'
                'BUILTIN\Administrators                 Alias            S-1-5-32-544 Group used for deny only'
            ) -join "`n"
            ConvertFrom-IgniteWhoamiGroups -Text $text | Should -Be @('S-1-1-0', 'S-1-5-32-544')
        }
    }

    Context 'ConvertTo-IgniteWslPath' {
        It 'maps <in> to <out>' -ForEach @(
            @{ in = 'C:\Users\henry\.config\ignite\ca.pem'; out = '/mnt/c/Users/henry/.config/ignite/ca.pem' }
            @{ in = 'C:\Users\A B\x.pem'; out = '/mnt/c/Users/A B/x.pem' }
            @{ in = 'd:\certs\corp.pem'; out = '/mnt/d/certs/corp.pem' }
        ) {
            ConvertTo-IgniteWslPath -Path $in | Should -Be $out
        }
    }

    Context 'Get-IgniteLinuxOneLiner' {
        It 'has no CA handling without a CA' {
            Get-IgniteLinuxOneLiner -CaWslPath $null |
                Should -Be 'curl -fsSL https://raw.githubusercontent.com/henrypham67/ignite/main/bootstrap.sh | bash'
        }

        It 'passes the CA to curl and to the bootstrap' {
            Get-IgniteLinuxOneLiner -CaWslPath '/mnt/c/Users/h/.config/ignite/ca.pem' |
                Should -Be "curl --cacert '/mnt/c/Users/h/.config/ignite/ca.pem' -fsSL https://raw.githubusercontent.com/henrypham67/ignite/main/bootstrap.sh | IGNITE_CA_CERT='/mnt/c/Users/h/.config/ignite/ca.pem' bash"
        }

        It 'keeps a path with spaces in one shell word' {
            Get-IgniteLinuxOneLiner -CaWslPath '/mnt/c/Users/A B/ca.pem' |
                Should -BeLike "curl --cacert '/mnt/c/Users/A B/ca.pem' *IGNITE_CA_CERT='/mnt/c/Users/A B/ca.pem' bash"
        }

        It "escapes a single quote in the path" {
            Get-IgniteLinuxOneLiner -CaWslPath "/mnt/c/Users/O'Neil/ca.pem" |
                Should -BeLike "*IGNITE_CA_CERT='/mnt/c/Users/O'\''Neil/ca.pem' bash"
        }
    }

    Context 'Get-IgniteChezmoiArgs' {
        BeforeEach {
            Mock Test-IgniteGitAvailable { $true }
        }

        It 'defaults to the public repo URL' {
            $a = Get-IgniteChezmoiArgs -Forward @()
            $a.Global | Should -BeNullOrEmpty
            $a.Init | Should -Be @('init', 'https://github.com/henrypham67/ignite.git')
        }

        It 'honours IGNITE_REPO and IGNITE_REF' {
            $env:IGNITE_REPO = 'someone/fork'
            $env:IGNITE_REF = 'dev'
            (Get-IgniteChezmoiArgs -Forward @()).Init |
                Should -Be @('init', 'https://github.com/someone/fork.git', '--branch', 'dev')
        }

        It 'uses --source for a local checkout' {
            $env:IGNITE_LOCAL_SOURCE = 'C:\src\ignite'
            $a = Get-IgniteChezmoiArgs -Forward @()
            $a.Global | Should -Be @('--source', 'C:\src\ignite')
            $a.Init | Should -Be @('init')
        }

        It 'forwards extra args in order' {
            (Get-IgniteChezmoiArgs -Forward @('--no-tty', '--promptString', 'Work email for git=ci@example.com')).Init |
                Should -Be @('init', 'https://github.com/henrypham67/ignite.git', '--no-tty', '--promptString', 'Work email for git=ci@example.com')
        }

        It 'uses the built-in git when git is missing' {
            Mock Test-IgniteGitAvailable { $false }
            (Get-IgniteChezmoiArgs -Forward @()).Global | Should -Be @('--use-builtin-git', 'on')
        }

        It 'never passes --force' {
            $a = Get-IgniteChezmoiArgs -Forward @('--no-tty')
            @($a.Global) + @($a.Init) | Should -Not -Contain '--force'
        }
    }

    Context 'Set-IgniteExecutionPolicy' {
        It 'leaves a policy alone that already lets scripts run' -ForEach @('RemoteSigned', 'Bypass', 'Unrestricted', 'AllSigned') {
            Mock Get-ExecutionPolicy { $_ }
            Mock Set-ExecutionPolicy {}
            Set-IgniteExecutionPolicy
            Should -Invoke Set-ExecutionPolicy -Times 0
        }

        It 'sets RemoteSigned for the user when scripts are blocked' {
            Mock Get-ExecutionPolicy { 'Restricted' }
            Mock Set-ExecutionPolicy {}
            Set-IgniteExecutionPolicy
            Should -Invoke Set-ExecutionPolicy -Times 1 -ParameterFilter { $ExecutionPolicy -eq 'RemoteSigned' -and $Scope -eq 'CurrentUser' }
        }

        It 'does not stop the run when the policy is overridden elsewhere' {
            Mock Get-ExecutionPolicy { 'Undefined' }
            Mock Set-ExecutionPolicy { throw 'ExecutionPolicyOverride' }
            $ErrorActionPreference = 'Stop'
            { Set-IgniteExecutionPolicy } | Should -Not -Throw
        }
    }

    Context 'Test-IgniteWsl' {
        It 'returns false instead of throwing when wsl.exe writes an error' {
            function global:wsl.exe { Write-Error 'WSL is not enabled' }
            try {
                Mock Get-Command { [pscustomobject]@{ Name = 'wsl.exe' } } -ParameterFilter { $Name -eq 'wsl.exe' }
                $ErrorActionPreference = 'Stop'
                { Test-IgniteWsl } | Should -Not -Throw
                Test-IgniteWsl | Should -BeFalse
            }
            finally { Remove-Item function:global:wsl.exe }
        }
    }

    Context 'elevation' {
        It 'quotes the script path for the elevated PowerShell' {
            $argList = Get-IgniteElevatedArgument -Script 'C:\Users\A B\AppData\Local\Temp\ignite-admin.ps1'
            ($argList -join ' ') | Should -BeLike '*-File "C:\Users\A B\AppData\Local\Temp\ignite-admin.ps1"'
        }

        It 'reports a declined UAC prompt instead of throwing' {
            Mock Test-IgniteIsElevated { $false }
            Mock Start-Process { throw 'The operation was canceled by the user.' }
            Invoke-IgniteElevated -Command 'Write-Output hi' | Should -BeFalse
        }
    }

    Context 'Backup-IgniteTarget' {
        It 'copies existing targets into a backup folder, keeping their paths' {
            $fakeHome = Join-Path $TestDrive 'home'
            New-Item -ItemType Directory -Force -Path (Join-Path $fakeHome '.ssh') | Out-Null
            Set-Content -LiteralPath (Join-Path $fakeHome '.gitconfig') -Value 'company'
            Set-Content -LiteralPath (Join-Path $fakeHome '.ssh/config') -Value 'Host corp'
            $backup = Backup-IgniteTarget -HomePath $fakeHome -Paths @('.gitconfig', '.ssh/config', '.bashrc')
            Get-Content -LiteralPath (Join-Path $backup '.gitconfig') | Should -Be 'company'
            Get-Content -LiteralPath (Join-Path $backup '.ssh/config') | Should -Be 'Host corp'
            Test-Path -LiteralPath (Join-Path $backup '.bashrc') | Should -BeFalse
        }

        It 'returns nothing when there is nothing to save' {
            Backup-IgniteTarget -HomePath (Join-Path $TestDrive 'empty') -Paths @('.gitconfig') | Should -BeNullOrEmpty
        }
    }

    Context 'running through irm | iex' {
        It 'never exits from inside Main, and only exits at the top level when run from a file' {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($Bootstrap, [ref]$null, [ref]$null)
            $main = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Main' }, $true)
            $main.FindAll({ param($n) $n -is [System.Management.Automation.Language.ExitStatementAst] }, $true) | Should -BeNullOrEmpty
            $last = (Get-Content -LiteralPath $Bootstrap | Where-Object { $_ -match '\S' })[-1]
            $last | Should -Match 'PSCommandPath'
        }
    }

    Context 'Get-IgniteAdminCommand' {
        BeforeEach { $env:IGNITE_SKIP = $null }

        It 'installs git and PowerShell with winget and enables WSL' {
            $command = Get-IgniteAdminCommand -HasWinget $true -NeedsWsl $true
            $command | Should -Match 'winget install --id Git\.Git'
            $command | Should -Match 'winget install --id Microsoft\.PowerShell'
            $command | Should -Match 'wsl\.exe --install --no-distribution'
        }

        It 'leaves winget out when it is missing' {
            Get-IgniteAdminCommand -HasWinget $false -NeedsWsl $true | Should -Not -Match 'winget'
        }

        It 'leaves WSL out when it is already there or IGNITE_SKIP lists wsl' {
            Get-IgniteAdminCommand -HasWinget $true -NeedsWsl $false | Should -Not -Match 'wsl'
            $env:IGNITE_SKIP = 'docker-desktop,wsl'
            Get-IgniteAdminCommand -HasWinget $true -NeedsWsl $true | Should -Not -Match 'wsl'
        }
    }

    Context 'Resolve-IgniteCaPath' {
        It 'expands ~ and makes relative paths absolute' {
            $file = Join-Path $TestDrive 'corp.pem'
            Set-Content -LiteralPath $file -Value 'CA'
            Push-Location $TestDrive
            try {
                Resolve-IgniteCaPath -Path 'corp.pem' | Should -Be $file
            }
            finally { Pop-Location }
            $homeFile = Join-Path $HOME 'ignite-pester-ca.pem'
            Set-Content -LiteralPath $homeFile -Value 'CA'
            try {
                Resolve-IgniteCaPath -Path '~/ignite-pester-ca.pem' | Should -Be $homeFile
            }
            finally { Remove-Item -LiteralPath $homeFile }
        }

        It 'fails with IGNITE_CA_CERT not found for a missing file' {
            { Resolve-IgniteCaPath -Path (Join-Path $TestDrive 'nope.pem') } |
                Should -Throw '*IGNITE_CA_CERT not found:*nope.pem'
        }
    }

    Context 'Windows PowerShell 5.1 compatibility' {
        It 'parses without errors' {
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($Bootstrap, [ref]$tokens, [ref]$errors) | Out-Null
            $errors | Should -BeNullOrEmpty
        }

        It 'parses under powershell.exe 5.1 when available' {
            $legacy = Get-Command powershell.exe -ErrorAction SilentlyContinue
            if (-not $legacy) { Set-ItResult -Skipped -Because 'powershell.exe only exists on Windows' }
            $count = & $legacy.Source -NoProfile -Command "`$e = `$null; [void][System.Management.Automation.Language.Parser]::ParseFile('$Bootstrap', [ref]`$null, [ref]`$e); `$e.Count"
            $count | Should -Be '0'
        }

        It 'uses no PowerShell 7-only syntax' {
            $code = Get-Content -Raw -LiteralPath $Bootstrap
            # Strip comments so prose can mention these.
            $code = ($code -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
            foreach ($pattern in @('\?\?', '\?\.', '&&', '\|\|', '-Parallel', 'utf8NoBOM', '-AsHashtable', '\$IsWindows')) {
                $code | Should -Not -Match $pattern -Because "$pattern is not available in Windows PowerShell 5.1"
            }
        }
    }
}
