# Every Windows chezmoi script must render to valid PowerShell for both
# Windows fixture machines.

Describe 'rendered Windows scripts' {
    BeforeDiscovery {
        $repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:Cases = foreach ($fixture in @('windows-admin', 'windows-noadmin')) {
            foreach ($template in Get-ChildItem -Path (Join-Path $repo 'home/.chezmoiscripts') -Filter '*.ps1.tmpl') {
                @{ Fixture = $fixture; Template = $template.FullName; Name = $template.Name }
            }
        }
    }

    BeforeAll {
        . (Join-Path $PSScriptRoot 'helper.ps1')
    }

    It '<Name> parses for <Fixture>' -ForEach $Cases {
        $code = (Invoke-IgniteRender -Fixture $Fixture -Path $Template) -join "`n"
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$null, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }
}
