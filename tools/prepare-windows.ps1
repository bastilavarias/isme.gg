param([string]$Flutter = "flutter.bat")
$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("ismegg-wrapper-" + [guid]::NewGuid().ToString("N"))
try {
  & $Flutter create --no-pub --platforms=android --project-name ismegg --org gg.isme $temp
  if ($LASTEXITCODE -ne 0) { throw "Flutter scaffold failed." }
  $android = Join-Path $temp "android"
  $dest = Join-Path $project "android"
  foreach ($file in @("gradlew", "gradlew.bat", "gradle/wrapper/gradle-wrapper.jar")) {
    $from = Join-Path $android $file
    if (!(Test-Path $from)) { throw "Missing scaffold wrapper: $file. Run flutter run first to provision wrapper." }
    Copy-Item $from (Join-Path $dest $file) -Force
  }
  Write-Host "Wrapper files copied. Existing Gradle settings preserved."
} finally {
  if (Test-Path $temp) { Remove-Item $temp -Recurse -Force }
}
