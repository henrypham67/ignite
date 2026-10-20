# Point Windows Terminal at PowerShell 7, Hack Nerd Font and Catppuccin Mocha.
# Windows Terminal owns settings.json, so only these three values are touched,
# and the file is rewritten only when one of them differs. Returns $true when
# it wrote the file.
function Update-IgniteTerminalSettings {
    param([Parameter(Mandatory)][string]$Path)
    $pwshProfile = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
    $settings = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -AsHashtable
    $changed = $false

    if ($settings['defaultProfile'] -ne $pwshProfile) {
        $settings['defaultProfile'] = $pwshProfile
        $changed = $true
    }

    $profiles = $settings['profiles']
    if ($null -eq $profiles -or $profiles -is [System.Collections.IList]) {
        $profiles = [ordered]@{ defaults = [ordered]@{}; list = @($profiles | Where-Object { $_ }) }
        $settings['profiles'] = $profiles
        $changed = $true
    }
    if ($null -eq $profiles['defaults']) {
        $profiles['defaults'] = [ordered]@{}
        $changed = $true
    }
    $defaults = $profiles['defaults']
    if ($defaults['colorScheme'] -ne 'Catppuccin Mocha') {
        $defaults['colorScheme'] = 'Catppuccin Mocha'
        $changed = $true
    }
    if ($null -eq $defaults['font']) {
        $defaults['font'] = [ordered]@{}
    }
    if ($defaults['font']['face'] -ne 'Hack Nerd Font') {
        $defaults['font']['face'] = 'Hack Nerd Font'
        $changed = $true
    }

    if ($changed) {
        $settings | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
    }
    return $changed
}
