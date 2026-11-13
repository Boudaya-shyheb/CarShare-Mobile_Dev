$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$neonEnvPath = Join-Path $repoRoot '.env.local'
if (-not (Test-Path -LiteralPath $neonEnvPath)) {
    throw 'Neon connection variables are missing. Link the project with neon link first.'
}

$variables = @{}
foreach ($line in Get-Content -LiteralPath $neonEnvPath) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
        $variables[$Matches[1]] = $Matches[2].Trim('"').Trim("'")
    }
}

function Convert-NeonUrlToJdbc([string] $value) {
    $uri = [Uri]::new($value)
    if ($uri.Scheme -notin @('postgresql', 'postgres')) {
        throw 'The Neon connection URL must use the postgresql scheme.'
    }

    $credentials = [Uri]::UnescapeDataString($uri.UserInfo).Split(':', 2)
    if ($credentials.Length -ne 2) {
        throw 'The Neon connection URL does not contain a username and password.'
    }
    $script:databaseUsername = $credentials[0]
    $script:databasePassword = $credentials[1]

    $hostName = $uri.DnsSafeHost
    if ($uri.Port -gt 0 -and $uri.Port -ne 5432) {
        $hostName = "$hostName`:$($uri.Port)"
    }
    $query = $uri.Query.TrimStart('?') -replace '(^|&)channel_binding=', '$1channelBinding='
    $jdbc = "jdbc:postgresql://$hostName$($uri.AbsolutePath)"
    if ($query) {
        $jdbc += "?$query"
    }
    return $jdbc
}

if (-not $variables.ContainsKey('DATABASE_URL')) {
    throw 'DATABASE_URL was not found in the Neon environment file.'
}

$env:DATABASE_URL = Convert-NeonUrlToJdbc $variables['DATABASE_URL']
$env:DATABASE_USERNAME = $script:databaseUsername
$env:DATABASE_PASSWORD = $script:databasePassword
$previousPort = $env:PORT
if ([string]::IsNullOrWhiteSpace($env:PORT)) {
    $env:PORT = '8081'
}
if ($variables.ContainsKey('DATABASE_URL_UNPOOLED')) {
    $env:DATABASE_URL_UNPOOLED = Convert-NeonUrlToJdbc $variables['DATABASE_URL_UNPOOLED']
}

# Load authentication and email settings from the same local file explicitly.
# This keeps the backend launcher independent from the shell's current directory
# and avoids stale, empty process environment variables overriding these values.
foreach ($name in @(
    'GOOGLE_SERVER_CLIENT_ID',
    'MAIL_HOST', 'MAIL_PORT', 'MAIL_USERNAME', 'MAIL_PASSWORD', 'MAIL_FROM',
    'MAIL_SMTP_AUTH', 'MAIL_SMTP_STARTTLS'
)) {
    if ($variables.ContainsKey($name)) {
        Set-Item -Path "Env:$name" -Value $variables[$name]
    }
}

# Support analyses uploaded evidence with Apache Tika, which runs in Docker. Start it when Docker is
# available (a no-op if it is already up); otherwise carry on: the analysis is then saved as partial.
function Start-SupportTika {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if (Get-Command docker -ErrorAction SilentlyContinue) {
            & docker info *> $null
            if ($LASTEXITCODE -eq 0) {
                Write-Host 'Starting Apache Tika for Support (docker compose)...'
                & docker compose -f (Join-Path $PSScriptRoot 'support-tika-compose.yml') up -d *> $null
                if ($LASTEXITCODE -eq 0) { return }
            }
        }
    }
    catch { }
    finally { $ErrorActionPreference = $previousPreference }
    Write-Host 'Docker is not available, so Apache Tika was not started: Support evidence analysis will be partial (file hash and type only).' -ForegroundColor Yellow
}

Push-Location -LiteralPath $PSScriptRoot
try {
    Start-SupportTika
    if ($env:OS -eq 'Windows_NT' -and $env:JAVA_TOOL_OPTIONS -notmatch 'javax\.net\.ssl\.trustStoreType') {
        $env:JAVA_TOOL_OPTIONS = (@($env:JAVA_TOOL_OPTIONS, '-Djavax.net.ssl.trustStoreType=Windows-ROOT') -join ' ').Trim()
    }
    Write-Host 'Starting CarShare API with the linked Neon database...'
    & (Join-Path $PSScriptRoot 'gradlew.bat') bootRun
    $exitCode = $LASTEXITCODE
}
finally {
    Pop-Location
    $env:PORT = $previousPort
}
exit $exitCode
