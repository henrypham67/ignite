# Hack Nerd Font as a per-user font (no admin): copy into the user font folder
# and register each file under HKCU.
$tmp = Join-Path ([IO.Path]::GetTempPath()) "ignite-font-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.zip' -OutFile (Join-Path $tmp 'Hack.zip')
    Expand-Archive -LiteralPath (Join-Path $tmp 'Hack.zip') -DestinationPath (Join-Path $tmp 'fonts')
    $dest = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $key = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
    Get-ChildItem -LiteralPath (Join-Path $tmp 'fonts') -Filter '*.ttf' | ForEach-Object {
        $target = Join-Path $dest $_.Name
        Copy-Item -LiteralPath $_.FullName -Destination $target -Force
        New-ItemProperty -Path $key -Name "$($_.BaseName) (TrueType)" -Value $target -PropertyType String -Force | Out-Null
    }
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
