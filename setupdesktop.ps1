param(
    [switch]$Test,
    [switch]$Build
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$pin = Get-Content (Join-Path $root 'toolchain.json') -Raw | ConvertFrom-Json
if ($env:ISME_FLUTTER_DIR) {
    $flutter = Join-Path $env:ISME_FLUTTER_DIR 'bin\flutter.bat'
    $dart = Join-Path $env:ISME_FLUTTER_DIR 'bin\dart.bat'
} else {
    $flutter = (Get-Command flutter -ErrorAction Stop).Source
    $dart = (Get-Command dart -ErrorAction Stop).Source
}
function Invoke-Flutter {
    & $flutter @args
    if ($LASTEXITCODE -ne 0) { throw "Flutter failed ($LASTEXITCODE): $args" }
}
$version = & $flutter --version --machine | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $version.frameworkVersion -ne $pin.flutter -or $version.dartSdkVersion -ne $pin.dart) {
    throw "Required Flutter $($pin.flutter) / Dart $($pin.dart)."
}
Push-Location $root
try {
    & $dart tools/prepare_fonts.dart
    if ($LASTEXITCODE -ne 0) { throw 'Font preparation failed.' }
    Push-Location (Join-Path $root 'desktop')
    try {
        if (-not (Test-Path 'windows/CMakeLists.txt')) {
            Invoke-Flutter create --platforms=windows --project-name ismegg_desktop --org gg.isme --no-pub --empty .
        }
        Invoke-Flutter pub get
        if ($Test -or $Build) {
            Invoke-Flutter analyze --no-pub
            Invoke-Flutter test --no-pub
        }
        if ($Build) {
            Invoke-Flutter build windows --release --no-pub
        } elseif (-not $Test) {
            Invoke-Flutter run -d windows --no-pub
        }
    } finally { Pop-Location }
} finally { Pop-Location }
