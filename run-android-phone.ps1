$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$localProperties = Join-Path $repoRoot 'android\local.properties'
if (-not (Test-Path -LiteralPath $localProperties)) {
    throw 'Android SDK location is missing. Open the project in Android Studio first.'
}

$sdkEntry = Get-Content -LiteralPath $localProperties |
    Where-Object { $_ -match '^sdk\.dir=' } |
    Select-Object -First 1
if (-not $sdkEntry) {
    throw 'The Android SDK location (sdk.dir) was not found in android/local.properties.'
}

$sdkPath = ($sdkEntry -replace '^sdk\.dir=', '').Replace('\\', '\')
$adb = Join-Path $sdkPath 'platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb)) {
    throw "Android Debug Bridge was not found at $adb. Install Android SDK Platform-Tools."
}

$devices = & $adb devices
$authorizedDevices = @($devices | Where-Object { $_ -match '^\S+\s+device$' })
if ($authorizedDevices.Count -eq 0) {
    throw 'No authorized Android device found. Connect the phone by USB and accept its USB debugging prompt.'
}

$apiPort = 8081
& $adb reverse "tcp:$apiPort" "tcp:$apiPort"
if ($LASTEXITCODE -ne 0) {
    throw 'Could not forward API port 8081. Check the USB connection and try again.'
}

$buildTemp = Join-Path $repoRoot '.dart_tool\codex-temp'
New-Item -ItemType Directory -Path $buildTemp -Force | Out-Null
$previousTemp = $env:TEMP
$previousTmp = $env:TMP
$previousJavaToolOptions = $env:JAVA_TOOL_OPTIONS
$env:TEMP = $buildTemp
$env:TMP = $buildTemp
$javaTempOption = "-Djava.io.tmpdir=$buildTemp"
$env:JAVA_TOOL_OPTIONS = (@($previousJavaToolOptions, $javaTempOption) |
    Where-Object { $_ }) -join ' '

Push-Location -LiteralPath $repoRoot
try {
    $flutterArgs = @('--dart-define=CARSHARE_API_BASE_URL=http://127.0.0.1:' + $apiPort + '/api')
    if ($env:GOOGLE_SERVER_CLIENT_ID) {
        $flutterArgs += '--dart-define=GOOGLE_SERVER_CLIENT_ID=' + $env:GOOGLE_SERVER_CLIENT_ID
    }
    if ($env:FACEBOOK_APP_ID) {
        $flutterArgs += '--dart-define=FACEBOOK_APP_ID=' + $env:FACEBOOK_APP_ID
        $flutterArgs += '-PfacebookAppId=' + $env:FACEBOOK_APP_ID
    }
    if ($env:FACEBOOK_CLIENT_TOKEN) {
        $flutterArgs += '-PfacebookClientToken=' + $env:FACEBOOK_CLIENT_TOKEN
    }
    flutter run @flutterArgs
    exit $LASTEXITCODE
}
finally {
    Pop-Location
    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp
    $env:JAVA_TOOL_OPTIONS = $previousJavaToolOptions
}
