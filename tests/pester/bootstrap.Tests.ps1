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
            # Like the real wsl.exe without WSL: an error, and a non-zero exit code.
            function global:wsl.exe { $global:LASTEXITCODE = 1; Write-Error 'WSL is not enabled' }
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

        It 'only installs git and PowerShell 7 when they are missing' {
            # Reinstalling PowerShell 7 closes every running pwsh, including
            # the window the bootstrap was started from.
            $command = Get-IgniteAdminCommand -HasWinget $true -NeedsWsl $false -NeedsGit $false -NeedsPwsh $false
            $command | Should -Not -Match 'Git\.Git'
            $command | Should -Not -Match 'Microsoft\.PowerShell'
            Get-IgniteAdminCommand -HasWinget $true -NeedsWsl $false -NeedsGit $false -NeedsPwsh $true |
                Should -Match 'Microsoft\.PowerShell'
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

    Context 'gum questions' {
        BeforeAll {
            $script:Repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
            # The stub gum answers each call with the next queued "rc|output"
            # line (\n separates multi-select picks) and logs its arguments.
            $script:GumStub = Join-Path $TestDrive 'gum.ps1'
            $script:GumQueue = Join-Path $TestDrive 'gum-answers.txt'
            $script:GumCalls = Join-Path $TestDrive 'gum-calls.txt'
            Set-Content -LiteralPath $GumStub -Value @'
Add-Content -LiteralPath (Join-Path $PSScriptRoot 'gum-calls.txt') -Value ($args -join ' ')
$queue = Join-Path $PSScriptRoot 'gum-answers.txt'
$lines = @(Get-Content -LiteralPath $queue)
if ($lines.Count -eq 0) { [Console]::Error.WriteLine("gum stub: no answer queued for: $args"); exit 99 }
Set-Content -LiteralPath $queue -Value @($lines | Select-Object -Skip 1)
$rc, $out = $lines[0] -split '\|', 2
if ($out) { $out -split '\\n' }
exit ([int]$rc)
'@
            function Set-GumAnswer {
                param([string[]]$Answer)
                Set-Content -LiteralPath $GumQueue -Value $Answer
                Set-Content -LiteralPath $GumCalls -Value @()
            }

            # Render the config template with chezmoi init's flags, no existing config.
            function Invoke-IgniteConfigRender {
                param([string[]]$Flags)
                $state = Join-Path $TestDrive "state-$([guid]::NewGuid()).boltdb"
                $template = Join-Path $Repo 'home/.chezmoi.toml.tmpl'
                $out = & chezmoi --source $Repo --config (Join-Path $TestDrive 'no-config.toml') --persistent-state $state `
                    execute-template --init --no-tty @Flags --file $template
                if ($LASTEXITCODE -ne 0) { throw 'chezmoi execute-template failed' }
                return ($out -join "`n")
            }
        }

        BeforeEach {
            $env:IGNITE_NO_GUM = $null
        }

        It 'passes the answers to the config template under its prompt keys' {
            Mock Get-IgniteChoiceMenu { @("editor`tvscode`tvscode zed") }
            Set-GumAnswer @('0|dev@example.com', '0|gitlab', '0|https://gitlab.example.com', '0|aws\ngcp', '0|',
                '0|specialist\npersonal', '0|', '0|zed')
            $flags = @(Get-IgniteAnswers -Gum $GumStub -Chezmoi 'chezmoi' -ChezmoiArgs ([pscustomobject]@{ Global = @(); Init = @('init') }))
            $config = Invoke-IgniteConfigRender -Flags $flags
            $config | Should -Match "(?m)^\s*email = .dev@example\.com.$"
            $config | Should -Match "(?m)^\s*git_host = .gitlab.$"
            $config | Should -Match "(?m)^\s*gitlab_url = .https://gitlab\.example\.com.$"
            $config | Should -Match '(?m)^\s*cloud_aws = true$'
            $config | Should -Match '(?m)^\s*cloud_azure = false$'
            $config | Should -Match '(?m)^\s*cloud_gcp = true$'
            $config | Should -Match '(?m)^\s*group_specialist = true$'
            $config | Should -Match '(?m)^\s*group_personal = true$'
            $config | Should -Match '(?m)^\s*customize_choices = true$'
            $config | Should -Match "(?m)^\s*editor = .zed.$"
            # The template only asks about Docker Desktop on Windows and macOS hosts.
            if (-not $IsLinux) { $config | Should -Match '(?m)^\s*docker_licensed = true$' }
        }

        It 'asks again for an email without @ and a GitLab URL without https://' {
            Set-GumAnswer @('0|', '0|dev@example.com', '0|gitlab', '0|gitlab.example.com', '0|https://gitlab.example.com',
                '0|', '1|', '0|', '1|')
            $flags = @(Get-IgniteAnswers -Gum $GumStub)
            $flags | Should -Contain 'Work email for git=dev@example.com'
            $flags | Should -Contain 'Company GitLab URL=https://gitlab.example.com'
            $flags | Should -Contain 'Company licenses Docker Desktop=false'
            $flags | Should -Contain 'Change default tool choices=false'
            @(Get-Content -LiteralPath $GumCalls | Where-Object { $_ -like 'input *' }).Count | Should -Be 4
        }

        It 'stops the setup on Ctrl-C' {
            Set-GumAnswer @('130|')
            { Get-IgniteAnswers -Gum $GumStub } | Should -Throw '*setup cancelled*'
            # A yes/no question: exit 1 is "no", 130 is Ctrl-C.
            Set-GumAnswer @('0|dev@example.com', '0|github', '0|', '130|')
            { Get-IgniteAnswers -Gum $GumStub } | Should -Throw '*setup cancelled*'
        }

        It 'names tools in the group labels that the catalog has in that group on Windows' {
            foreach ($group in @('specialist', 'personal')) {
                $label, $value = (Get-IgniteGroupLabel -Group $group) -split '\|', 2
                $value | Should -Be $group
                foreach ($name in (($label -split ': ', 2)[1] -split ', ')) {
                    $template = "{{ `$p := index .packages `"$name`" }}{{ `$p.group }} {{ if hasKey `$p `"platforms`" }}{{ `$p.platforms | join `" `" }}{{ else }}windows{{ end }}"
                    $state = Join-Path $TestDrive "state-$([guid]::NewGuid()).boltdb"
                    $out = $template | & chezmoi --source $Repo --config (Join-Path $Repo 'tests/fixtures/config/windows-admin.toml') `
                        --persistent-state $state execute-template
                    $LASTEXITCODE | Should -Be 0 -Because "$name should be in the catalog"
                    $found, $platforms = "$out" -split ' ', 2
                    $found | Should -Be $group -Because "$name is listed as a $group tool"
                    " $platforms " | Should -BeLike '* windows *' -Because "$name should be available on Windows"
                }
            }
        }

        It 'fetches a remote repo with the answers so far, then reads the menu from the config template' {
            $stub = Join-Path $TestDrive 'chezmoi.ps1'
            $log = Join-Path $TestDrive 'chezmoi-calls.txt'
            Set-Content -LiteralPath $stub -Value @"
Add-Content -LiteralPath '$log' -Value (`$args -join ' ')
if (`$args -contains 'source-path') { '/src/home' }
if (`$args -contains 'execute-template') { if (`$env:IGNITE_CHOICE_MENU -eq '1') { "editor``tvscode``tvscode zed" } else { 'not menu mode' } }
exit 0
"@
            $menu = @(Get-IgniteChoiceMenu -Chezmoi $stub -InitArgs @('init', 'https://github.com/henrypham67/ignite.git') `
                    -Answers @('--promptString', 'Work email for git=dev@example.com'))
            $menu | Should -Be @("editor`tvscode`tvscode zed")
            $calls = @(Get-Content -LiteralPath $log)
            # The email has no default, so --promptDefaults alone would stop at its prompt.
            $calls[0] | Should -BeLike 'init https://github.com/henrypham67/ignite.git --promptString Work email for git=dev@example.com --promptDefaults --config-path *'
            $calls[-1] | Should -BeLike 'execute-template --init * --file *.chezmoi.toml.tmpl'
            $env:IGNITE_CHOICE_MENU | Should -BeNullOrEmpty
        }

        It 'uses gum only on a first run in a console, without --no-tty or IGNITE_NO_GUM' {
            Mock Test-IgniteConsole { $true }
            Test-IgniteUseGum -FirstRun $true | Should -BeTrue
            Test-IgniteUseGum -FirstRun $false | Should -BeFalse
            Test-IgniteUseGum -FirstRun $true -Forward @('--no-tty') | Should -BeFalse
            $env:IGNITE_NO_GUM = '1'
            Test-IgniteUseGum -FirstRun $true | Should -BeFalse
            $env:IGNITE_NO_GUM = $null
            Mock Test-IgniteConsole { $false }
            Test-IgniteUseGum -FirstRun $true | Should -BeFalse
        }

        It 'installs gum with mise from the home folder and returns its path' {
            $log = Join-Path $TestDrive 'mise-calls.txt'
            function global:mise {
                Add-Content -LiteralPath (Join-Path $TestDrive 'mise-calls.txt') -Value ($args -join ' ')
                $global:LASTEXITCODE = 0
                if ($args -contains 'which') { '/opt/gum/bin/gum' }
            }
            try {
                Install-IgniteGum | Should -Be '/opt/gum/bin/gum'
                # A mise.toml where the bootstrap was started can't stop the install with a trust prompt.
                @(Get-Content -LiteralPath $log)[0] | Should -Be "-C $HOME install gum@$IgniteGumVersion"
            }
            finally { Remove-Item Function:\global:mise }
        }

        It 'returns the answers as chezmoi init flags, or none when gum is missing' {
            Mock Test-IgniteConsole { $true }
            Mock Install-IgniteGum { $GumStub }
            Set-GumAnswer @('0|dev@example.com', '0|github', '0|', '1|', '0|', '1|')
            $flags = @(Get-IgniteGumAnswers -FirstRun $true)
            $flags[0..1] | Should -Be @('--promptString', 'Work email for git=dev@example.com')

            Mock Install-IgniteGum { $null }
            @(Get-IgniteGumAnswers -FirstRun $true).Count | Should -Be 0
            @(Get-IgniteGumAnswers -FirstRun $false).Count | Should -Be 0
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
