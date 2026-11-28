param(
    [switch]$Test,
    [switch]$Build,
    [switch]$Engine
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$pin = Get-Content (Join-Path $root 'toolchain.json') -Raw | ConvertFrom-Json
if ($env:ISME_FLUTTER_DIR -and (Test-Path (Join-Path $env:ISME_FLUTTER_DIR 'bin\flutter.bat'))) {
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
    if ($Build -or $Engine) {
        $maven = (Get-Command mvn -ErrorAction Stop).Source
        & $maven -B -f (Join-Path $root 'desktop\native-engine\pom.xml') clean package
        if ($LASTEXITCODE -ne 0) { throw 'Native desktop engine build failed.' }
    }
    $engineTarget = Join-Path $root 'desktop\native-engine\target'
    if (Test-Path (Join-Path $engineTarget 'classes')) {
        $env:ISME_DESKTOP_ENGINE = $engineTarget
    }
    Push-Location (Join-Path $root 'desktop')
    try {
        if (-not (Test-Path 'windows/CMakeLists.txt')) {
            Invoke-Flutter create --platforms=windows --project-name ismegg_desktop --org gg.isme --no-pub --empty .
        }
        Invoke-Flutter pub get
        if ($Test -or $Build) {
            Invoke-Flutter analyze --no-pub --no-fatal-infos
            Invoke-Flutter test --no-pub
        }
        if ($Build) {
            Invoke-Flutter build windows --release --no-pub
            $release = Join-Path (Get-Location) 'build\windows\x64\runner\Release'
            $engineDir = Join-Path $release 'engine'
            New-Item -ItemType Directory -Force $engineDir | Out-Null
            Copy-Item 'native-engine\target\classes' $engineDir -Recurse -Force
            Copy-Item 'native-engine\target\dependency' $engineDir -Recurse -Force
            $jlink = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin\jlink.exe' } else { (Get-Command jlink -ErrorAction Stop).Source }
            $runtime = Join-Path $engineDir 'runtime'
            if (!(Test-Path (Join-Path $runtime 'bin\java.exe'))) {
                & $jlink --add-modules java.se,jdk.httpserver,jdk.unsupported,jdk.crypto.ec,jdk.zipfs --output $runtime --strip-debug --no-header-files --no-man-pages
                if ($LASTEXITCODE -ne 0) { throw 'Java runtime packaging failed.' }
            }
        } elseif (-not $Test) {
            Invoke-Flutter run -d windows --no-pub
        }
    } finally { Pop-Location }
} finally { Pop-Location }
