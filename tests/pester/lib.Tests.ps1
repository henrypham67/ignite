# lib.ps1: the report helpers rendered into every Windows install script.

Describe 'lib.ps1' {
    BeforeAll {
        $script:Repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        . (Join-Path $PSScriptRoot 'helper.ps1')
        $script:Lib = Join-Path $TestDrive 'lib.ps1'
        Invoke-IgniteRender -Fixture 'windows-admin' -Path (Join-Path $Repo 'home/.chezmoitemplates/lib.ps1') |
            Set-Content -LiteralPath $Lib
        . $Lib
    }

    BeforeEach {
        $env:LOCALAPPDATA = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $env:IGNITE_SKIP = $null
        $script:Report = Join-Path $env:LOCALAPPDATA 'ignite/report.tsv'
    }

    It 'Get-IgniteReportPath lives under LOCALAPPDATA' {
        Get-IgniteReportPath | Should -Be $Report
    }

    It 'Invoke-IgniteTry records a thrown failure and does not throw' {
        { Invoke-IgniteTry -Source mise -Item k9s -ScriptBlock { Write-Output 'first'; throw 'boom' } } |
            Should -Not -Throw
        Get-Content -LiteralPath $Report | Should -Be "mise`tfailed`tk9s`tboom"
    }

    It 'Invoke-IgniteTry records a native command failure with its last output line' {
        Invoke-IgniteTry -Source winget -Item git -ScriptBlock { pwsh -NoProfile -Command 'Write-Output first; Write-Output last; exit 3' }
        Get-Content -LiteralPath $Report | Should -Be "winget`tfailed`tgit`tlast"
    }

    It 'Invoke-IgniteTry success writes no row' {
        Invoke-IgniteTry -Source mise -Item jq -ScriptBlock { Write-Output 'fine' }
        Test-Path -LiteralPath $Report | Should -BeFalse
    }

    It 'Reset-IgniteReport removes only its source' {
        Add-IgniteReport -Source mise -Status failed -Item k9s -Detail one
        Add-IgniteReport -Source scoop -Status failed -Item git -Detail two
        Reset-IgniteReport -Source mise
        Get-Content -LiteralPath $Report | Should -Be "scoop`tfailed`tgit`ttwo"
    }

    It 'IGNITE_SKIP records skipped and does not run the script block' {
        $marker = Join-Path $TestDrive 'marker'
        $env:IGNITE_SKIP = 'docker-desktop,k9s'
        Invoke-IgniteTry -Source mise -Item k9s -ScriptBlock { New-Item -ItemType File -Path $marker }
        Test-Path -LiteralPath $marker | Should -BeFalse
        Get-Content -LiteralPath $Report | Should -Be "mise`tskipped`tk9s`tIGNITE_SKIP"
    }

    It 'rate-limit failure adds the GITHUB_TOKEN hint' {
        Invoke-IgniteTry -Source mise -Item kubectl -ScriptBlock { throw 'GitHub API rate limit exceeded for 203.0.113.9' }
        Get-Content -LiteralPath $Report | Should -Match 'rate limit exceeded.*set GITHUB_TOKEN and retry$'
    }

    It 'detail strips tabs and newlines' {
        Add-IgniteReport -Source scoop -Status failed -Item git -Detail "a`tb`nc"
        $lines = @(Get-Content -LiteralPath $Report)
        $lines.Count | Should -Be 1
        ($lines[0] -split "`t").Count | Should -Be 4
    }
}
