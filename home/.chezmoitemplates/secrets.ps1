# Make sure the secrets file exists, only the current user can read it, and it
# lists every expected name. Existing lines are never rewritten; missing names
# are added with an empty value for the owner to fill in.
function Sync-IgniteSecretsFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowEmptyCollection()][string[]]$Names = @()
    )
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if (-not (Test-Path -LiteralPath $Path)) {
        Set-Content -LiteralPath $Path -Value '# ignite secrets: fill in the values. Never committed; loaded by your profile.' -Encoding utf8NoBOM
    }
    if ($IsWindows) {
        $acl = Get-Acl -LiteralPath $Path
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($rule in @($acl.Access)) { [void]$acl.RemoveAccessRule($rule) }
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($me, 'FullControl', 'Allow')))
        Set-Acl -LiteralPath $Path -AclObject $acl
    }
    $existing = Get-Content -Raw -LiteralPath $Path
    foreach ($name in $Names) {
        if ($existing -notmatch "(?m)^\s*\`$env:$name\s*=") {
            Add-Content -LiteralPath $Path -Value "`$env:$name = ''" -Encoding utf8NoBOM
        }
    }
}
