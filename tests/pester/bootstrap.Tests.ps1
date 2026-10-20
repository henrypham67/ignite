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
            Get-IgniteChezmoiArgs -Forward @() |
                Should -Be @('init', '--apply', 'https://github.com/henrypham67/ignite.git')
        }

        It 'honours IGNITE_REPO and IGNITE_REF' {
            $env:IGNITE_REPO = 'someone/fork'
            $env:IGNITE_REF = 'dev'
            Get-IgniteChezmoiArgs -Forward @() |
                Should -Be @('init', '--apply', 'https://github.com/someone/fork.git', '--branch', 'dev')
        }

        It 'uses --source for a local checkout' {
            $env:IGNITE_LOCAL_SOURCE = 'C:\src\ignite'
            Get-IgniteChezmoiArgs -Forward @() | Should -Be @('init', '--apply', '--source', 'C:\src\ignite')
        }

        It 'forwards extra args in order' {
            Get-IgniteChezmoiArgs -Forward @('--no-tty', '--promptString', 'Work email for git=ci@example.com') |
                Should -Be @('init', '--apply', 'https://github.com/henrypham67/ignite.git', '--no-tty', '--promptString', 'Work email for git=ci@example.com')
        }

        It 'uses the built-in git when git is missing' {
            Mock Test-IgniteGitAvailable { $false }
            (Get-IgniteChezmoiArgs -Forward @())[0..2] | Should -Be @('--use-builtin-git', 'on', 'init')
        }

        It 'never passes --force' {
            Get-IgniteChezmoiArgs -Forward @('--no-tty') | Should -Not -Contain '--force'
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
