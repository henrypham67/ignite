# PowerShell profile, the $PROFILE shim and the Windows Terminal settings update.

Describe 'PowerShell profile and Windows Terminal' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'helper.ps1')
        $script:Templates = Join-Path $IgniteRepo 'home/.chezmoitemplates'
        foreach ($name in @('pwsh-profile-shim.ps1', 'windows-terminal-settings.ps1')) {
            $out = Join-Path $TestDrive $name
            Invoke-IgniteRender -Fixture 'windows-admin' -Path (Join-Path $Templates $name) | Set-Content -LiteralPath $out
            . $out
        }
        $script:Profile = Join-Path $TestDrive 'profile.ps1'
        Invoke-IgniteRender -Fixture 'windows-admin' -Path (Join-Path $IgniteRepo 'home/dot_config/powershell/profile.ps1.tmpl') |
            Set-Content -LiteralPath $Profile
        $script:Pwsh = (Get-Process -Id $PID).Path
    }

    Context 'Install-IgniteProfileShim' {
        It 'writes once under a redirected path' {
            $profilePath = Join-Path $TestDrive 'OneDrive - Example\Documents\PowerShell\profile.ps1'
            Test-Path -LiteralPath (Split-Path -Parent $profilePath) | Should -BeFalse
            Install-IgniteProfileShim -ProfilePath $profilePath
            Install-IgniteProfileShim -ProfilePath $profilePath
            $lines = @(Get-Content -LiteralPath $profilePath)
            @($lines | Where-Object { $_ -like '*.config*powershell*profile.ps1*' }).Count | Should -Be 1
        }

        It 'keeps a last line that has no newline intact, and adds the shim once' {
            $profilePath = Join-Path $TestDrive 'no-newline.ps1'
            [IO.File]::WriteAllText($profilePath, 'Import-Module posh-git')
            Install-IgniteProfileShim -ProfilePath $profilePath
            Install-IgniteProfileShim -ProfilePath $profilePath
            $lines = @(Get-Content -LiteralPath $profilePath)
            $lines[0] | Should -Be 'Import-Module posh-git'
            @($lines | Where-Object { $_ -like '*.config*powershell*profile.ps1*' }).Count | Should -Be 1
        }

        It 'keeps what is already in the profile' {
            $profilePath = Join-Path $TestDrive 'existing.ps1'
            Set-Content -LiteralPath $profilePath -Value 'Set-Alias ll Get-ChildItem'
            Install-IgniteProfileShim -ProfilePath $profilePath
            (Get-Content -LiteralPath $profilePath)[0] | Should -Be 'Set-Alias ll Get-ChildItem'
        }
    }

    Context 'profile.ps1' {
        It 'parses without errors' {
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($Profile, [ref]$null, [ref]$errors) | Out-Null
            $errors | Should -BeNullOrEmpty
        }

        It 'defines k and kgp functions and loads with none of the tools installed' {
            $saved = $env:PATH
            try {
                $env:PATH = '/usr/bin' + [IO.Path]::PathSeparator + '/bin'
                $out = & $Pwsh -NoLogo -NoProfile -Command ". '$Profile'; (Get-Command k).CommandType; (Get-Command kgp).Definition.Trim(); (Get-Command gl).CommandType" 2>&1
            }
            finally { $env:PATH = $saved }
            $out[0] | Should -Be 'Function'
            $out[1] | Should -Be 'kubectl get pods @args'
            # gl must be the git alias, not PowerShell's Get-Location alias.
            $out[2] | Should -Be 'Function'
        }

        It 'kctx and kns use kubectx and kubens on Windows (krew has no Windows ctx/ns)' {
            $out = & $Pwsh -NoLogo -NoProfile -Command ". '$Profile'; (Get-Command kctx).Definition.Trim(); (Get-Command kns).Definition.Trim()" 2>&1
            $out[-2] | Should -Be 'kubectx @args'
            $out[-1] | Should -Be 'kubens @args'
        }

        It 'loads quietly when PSReadLine can''t set up the console (<Case>)' -ForEach @(
            @{ Case = 'error'; Stub = "Write-Error 'The handle is invalid.'" }
            @{ Case = 'throw'; Stub = "throw 'The handle is invalid.'" }
        ) {
            $stub = "function Set-PSReadLineOption { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]`$Rest) $Stub }"
            $out = @(& $Pwsh -NoLogo -NoProfile -Command "$stub; . '$Profile'; 'loaded'" 2>&1)
            ($out | ForEach-Object { "$_" }) -join "`n" | Should -Not -Match 'handle is invalid'
            "$($out[-1])" | Should -Be 'loaded'
        }

        It 'puts krew plugins on PATH, so kubectl finds kubectl-krew' {
            $saved = $env:PATH
            try {
                $env:PATH = '/usr/bin' + [IO.Path]::PathSeparator + '/bin'
                $out = & $Pwsh -NoLogo -NoProfile -Command ". '$Profile'; `$env:PATH" 2>&1
            }
            finally { $env:PATH = $saved }
            ($out -join "`n") | Should -Match '\.krew[\\/]bin'
        }

        It 'loads secrets and completions from their folders' {
            Get-Content -Raw -LiteralPath $Profile | Should -Match 'secrets\.ps1'
            Get-Content -Raw -LiteralPath $Profile | Should -Match '\.cache.ignite.completions'
        }
    }

    Context 'Update-IgniteTerminalSettings' {
        BeforeEach {
            $script:Settings = Join-Path $TestDrive "settings-$([guid]::NewGuid()).json"
            Set-Content -LiteralPath $Settings -Value @'
{
    // Windows Terminal writes comments into its settings file.
    "defaultProfile": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}",
    "profiles": { "defaults": {}, "list": [ { "name": "Windows PowerShell" } ] },
    "schemes": []
}
'@
        }

        It 'sets the default profile, font and color scheme' {
            Update-IgniteTerminalSettings -Path $Settings | Should -BeTrue
            $json = Get-Content -Raw -LiteralPath $Settings | ConvertFrom-Json
            $json.defaultProfile | Should -Be '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
            $json.profiles.defaults.font.face | Should -Be 'Hack Nerd Font'
            $json.profiles.defaults.colorScheme | Should -Be 'Catppuccin Mocha'
            $json.profiles.list[0].name | Should -Be 'Windows PowerShell'
        }

        It 'writes nothing when the values are already set' {
            Update-IgniteTerminalSettings -Path $Settings | Out-Null
            $before = Get-Content -Raw -LiteralPath $Settings
            Update-IgniteTerminalSettings -Path $Settings | Should -BeFalse
            Get-Content -Raw -LiteralPath $Settings | Should -BeExactly $before
        }

        It 'configures Windows Terminal once and then leaves the owner''s changes alone' {
            $marker = Join-Path $TestDrive "marker-$([guid]::NewGuid())"
            Invoke-IgniteTerminalSetup -SettingsPath $Settings -MarkerPath $marker | Should -Be 'updated'
            Test-Path -LiteralPath $marker | Should -BeTrue
            $json = Get-Content -Raw -LiteralPath $Settings | ConvertFrom-Json -AsHashtable
            $json['profiles']['defaults']['colorScheme'] = 'One Half Dark'
            $json | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $Settings
            Invoke-IgniteTerminalSetup -SettingsPath $Settings -MarkerPath $marker | Should -Be 'done-before'
            (Get-Content -Raw -LiteralPath $Settings | ConvertFrom-Json).profiles.defaults.colorScheme | Should -Be 'One Half Dark'
        }

        It 'reports a missing settings file and tries again next time' {
            $marker = Join-Path $TestDrive "marker-$([guid]::NewGuid())"
            Invoke-IgniteTerminalSetup -SettingsPath (Join-Path $TestDrive 'nope.json') -MarkerPath $marker | Should -Be 'no-settings'
            Test-Path -LiteralPath $marker | Should -BeFalse
        }

        It 'handles the older profiles-as-a-list format' {
            Set-Content -LiteralPath $Settings -Value '{ "profiles": [ { "name": "cmd" } ] }'
            Update-IgniteTerminalSettings -Path $Settings | Should -BeTrue
            $json = Get-Content -Raw -LiteralPath $Settings | ConvertFrom-Json
            $json.profiles.list[0].name | Should -Be 'cmd'
            $json.profiles.defaults.colorScheme | Should -Be 'Catppuccin Mocha'
        }
    }
}
