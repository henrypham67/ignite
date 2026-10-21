# Anthropic's native installer: per user, no admin.
& ([scriptblock]::Create((Invoke-RestMethod -UseBasicParsing -Uri 'https://claude.ai/install.ps1')))
