param(
    [string]$Avd,
    [switch]$TV,
    [Alias('Smartphone','Phone')][switch]$Mobile,
    [switch]$Both,
    [string]$TvAvd = 'ismegg_TV_API_36',
    [string]$MobileAvd = 'ismegg_Mobile_API_36',
    [switch]$SkipPull,
    [switch]$ReuseEmulator,
    [string]$JdkDir,
    [string]$FlutterDir,
    [switch]$CheckOnly,
    [switch]$BuildOnly
)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

function Invoke-Checked {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Exe failed (exit code $LASTEXITCODE)."
    }
}

function Find-Tool {
    param([string]$Name, [string[]]$Candidates = @())
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }
    throw "$Name not found. Install it or add it to your Windows PATH."
}

function Get-TrackedState {
    param([string]$Git, [string[]]$Paths)
    # NUL-delimited entries preserve spaces and Unicode paths. Hash on-disk bytes
    # so changes to an already modified file are detected as well.
    $encoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.Encoding]::UTF8
        $entries = (& $Git ls-files --stage -z -- @Paths) -join "`n"
        if ($LASTEXITCODE -ne 0) { throw 'Could not read the Git index.' }
    } finally {
        [Console]::OutputEncoding = $encoding
    }
    $state = @{}
    foreach ($entry in ($entries -split "`0" | Where-Object { $_ })) {
        $index, $path = $entry -split "`t", 2
        if (-not $index.EndsWith(' 0')) { throw "Resolve the Git conflict in $path before building." }
        $hash = if (Test-Path -LiteralPath $path -PathType Leaf) {
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        }
        $state[$path] = "$index|$hash"
    }
    return $state
}

function Assert-TrackedState {
    param([string]$Git, [hashtable]$Before, [string]$Stage, [string[]]$Paths)
    $after = Get-TrackedState $Git $Paths
    $changes = @(($Before.Keys + $after.Keys) | Sort-Object -Unique |
        Where-Object { $Before[$_] -cne $after[$_] })
    if ($changes.Count) {
        Write-Host "Tracked files changed at ${Stage} (changes preserved):" -ForegroundColor Yellow
        $changes | Write-Host
        throw "Tracked file verification failed at $Stage."
    }
}

function Find-PinnedFlutter {
    param([string]$Explicit, [string]$Version, [string]$DartVersion, [string[]]$Candidates)
    $paths = @()
    if ($Explicit) {
        $paths += (Join-Path $Explicit 'bin\flutter.bat')
    } else {
        foreach ($root in @($env:ISME_FLUTTER_DIR,$env:FLUTTER_ROOT)) {
            if ($root) { $paths += (Join-Path $root 'bin\flutter.bat') }
        }
        $paths += $Candidates
        $command = Get-Command flutter.bat -ErrorAction SilentlyContinue
        if ($command) { $paths += $command.Source }
    }
    foreach ($candidate in ($paths | Where-Object { $_ } | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        try {
            $raw = @(& $candidate --version --machine)
            if ($LASTEXITCODE -ne 0) { continue }
            $info = ($raw -join "`n") | ConvertFrom-Json
            if ($info.frameworkVersion -eq $Version -and $info.dartSdkVersion -eq $DartVersion) {
                return (Resolve-Path -LiteralPath $candidate).Path
            }
            Write-Host "Skipping Flutter $($info.frameworkVersion) / Dart $($info.dartSdkVersion); project requires $Version / $DartVersion." -ForegroundColor Yellow
        } catch {
            Write-Host "Could not inspect Flutter SDK at $candidate." -ForegroundColor Yellow
        }
    }
    throw "Flutter $Version with Dart $DartVersion is required. Add it to PATH, set ISME_FLUTTER_DIR, or pass -FlutterDir."
}

function Find-CompatibleJdk {
    param([string]$Explicit, [string]$Flutter, [string]$JavaVersion)
    $candidates = @($Explicit, $env:ISME_JDK_DIR, $env:JAVA_HOME)
    if ($Explicit) { $candidates = @($Explicit) }
    else {
        $java = Get-Command java.exe -ErrorAction SilentlyContinue
        if ($java) { $candidates += (Split-Path -Parent (Split-Path -Parent $java.Source)) }
        $roots = @()
        if ($env:ProgramFiles) {
            foreach ($vendor in @('Eclipse Adoptium','Microsoft','Java','Amazon Corretto','BellSoft','Zulu','Semeru')) {
                $roots += (Join-Path $env:ProgramFiles $vendor)
            }
            $candidates += (Join-Path $env:ProgramFiles 'Android\Android Studio\jbr')
        }
        if ($env:USERPROFILE) {
            $roots += (Join-Path $env:USERPROFILE '.jdks')
            $roots += (Join-Path $env:USERPROFILE 'scoop\apps')
        }
        $sdkParent = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $Flutter))
        $roots += $sdkParent
        foreach ($root in $roots) {
            if ($root -and (Test-Path -LiteralPath $root -PathType Container)) {
                $candidates += @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match '(?i)jdk|jbr|java|temurin|corretto|zulu' } |
                    ForEach-Object { $_.FullName; Join-Path $_.FullName 'current' })
            }
        }
    }
    foreach ($candidate in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        $jdkHome = $candidate.Trim('"')
        if (-not (Test-Path -LiteralPath (Join-Path $jdkHome 'bin\javac.exe') -PathType Leaf)) { continue }
        $release = Join-Path $jdkHome 'release'
        if (-not (Test-Path -LiteralPath $release -PathType Leaf)) { continue }
        $versionLine = Get-Content -LiteralPath $release | Where-Object { $_ -match '^JAVA_VERSION="' } | Select-Object -First 1
        if ($versionLine -match ('^JAVA_VERSION="' + [regex]::Escape($JavaVersion) + '(?:\.|"|-)')) {
            return (Resolve-Path -LiteralPath $jdkHome).Path
        }
    }
    throw "JDK $JavaVersion is required. Install Eclipse Temurin from https://adoptium.net/temurin/releases/ or pass -JdkDir to the correct JDK."
}

function Find-AvdSerial {
    param([string]$Adb, [string]$Name)
    $lines = & $Adb devices 2>$null
    foreach ($line in $lines) {
        if ($line -match '^(emulator-\d+)\s+device\s*$') {
            $serial = $Matches[1]
            $reply = @(& $Adb -s $serial emu avd name 2>$null)
            if ($LASTEXITCODE -eq 0 -and $reply -contains $Name) { return $serial }
        }
    }
    return $null
}

function Start-SelectedAvd {
    param([string]$Avd, [string]$Adb, [string]$Emulator, [bool]$ReuseEmulator)
    if ($ReuseEmulator) {
        Write-Host "Reusing $Avd when available..." -ForegroundColor Cyan
    } else {
        Write-Host "Cold-booting $Avd..." -ForegroundColor Cyan
    }
    $serial = Find-AvdSerial $adb $Avd
    $escaped = [regex]::Escape($Avd)
    function Get-MatchingEmulator {
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '^(emulator|qemu-system-.+)\.exe$' -and
                $_.CommandLine -match "(?i)(?:-avd\s+|@|\\avd\\)\x22?$escaped(?:\x22|\s|\.avd|$)"
            }
    }
    if ($serial -and -not $ReuseEmulator) {
        Write-Host "Stopping $Avd ($serial) before cold boot..."
        Invoke-Checked $adb @('-s', $serial, 'emu', 'kill') | Out-Host
        $deadline = (Get-Date).AddSeconds(45)
        do {
            Start-Sleep -Seconds 1
            $devices = @(& $adb devices 2>$null)
            $stillConnected = @($devices | Where-Object { $_ -match "^$serial\s" }).Count -gt 0
            $running = @(Get-MatchingEmulator)
        } while (($stillConnected -or $running.Count -gt 0) -and (Get-Date) -lt $deadline)
        if ($stillConnected -or $running.Count -gt 0) {
            throw "The emulator did not exit. Close $Avd manually and rerun."
        }
        $serial = $null
    }
    if (-not $serial) {
        $running = @(Get-MatchingEmulator)
        if ($running.Count -gt 0) {
            if (-not $ReuseEmulator) {
                throw "The target emulator is running but is not reachable through ADB. Close $Avd manually and rerun."
            }
            Write-Host 'Matching emulator is already starting.'
        } else {
            Write-Host 'Starting without loading a saved snapshot...'
            Start-Process -FilePath $emulator -ArgumentList @('-avd', ('"' + $Avd + '"'), '-no-snapshot-load')
        }
        $deadline = (Get-Date).AddMinutes(5)
        do {
            Start-Sleep -Seconds 2
            $serial = Find-AvdSerial $adb $Avd
        } until ($serial -or (Get-Date) -ge $deadline)
        if (-not $serial) { throw 'Emulator did not connect to ADB within five minutes.' }
    } else {
        Write-Host "Reusing $Avd ($serial)."
    }
    $deadline = (Get-Date).AddMinutes(5)
    do {
        $boot = @(& $adb -s $serial shell getprop sys.boot_completed 2>$null)
        if ($LASTEXITCODE -eq 0 -and ($boot -join '').Trim() -eq '1') { break }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    if (($boot -join '').Trim() -ne '1') { throw 'Android did not complete boot within five minutes.' }
    Write-Host "$Avd ready: $serial"
    return $serial
}

function Send-FlutterCommand {
    param($Session, [string]$Method, [hashtable]$Parameters)
    $Session.RequestId++
    $Parameters.appId = $Session.AppId
    $request = @{ id = $Session.RequestId; method = $Method; params = $Parameters } | ConvertTo-Json -Compress
    $Session.Process.StandardInput.WriteLine("[$request]")
    $Session.Process.StandardInput.Flush()
}

# Flutter only accepts a prebuilt APK with a single explicit device. Use its
# machine protocol to keep both device runs controlled by the same terminal.
function Invoke-BothFlutterRuns {
    param([string]$Flutter, [string[]]$Serials, [string]$Apk)
    $sessions = @()
    try {
        foreach ($serial in $Serials) {
            $start = New-Object System.Diagnostics.ProcessStartInfo
            $start.FileName = $env:ComSpec
            $start.Arguments = "/d /s /c `"`"%ISME_SESSION_FLUTTER%`" run --machine --debug --no-pub -d $serial --use-application-binary `"$Apk`"`""
            $start.EnvironmentVariables['ISME_SESSION_FLUTTER'] = $Flutter
            $start.UseShellExecute = $false
            $start.CreateNoWindow = $true
            $start.RedirectStandardInput = $true
            $start.RedirectStandardOutput = $true
            $start.StandardOutputEncoding = [Text.Encoding]::UTF8
            $process = [Diagnostics.Process]::Start($start)
            $sessions += [pscustomobject]@{
                Serial = $serial
                Process = $process
                Line = $process.StandardOutput.ReadLineAsync()
                AppId = $null
                RequestId = 0
                Started = $false
            }
        }

        while ($true) {
            foreach ($session in $sessions) {
                if (-not $session.Line.IsCompleted) { continue }
                $line = $session.Line.GetAwaiter().GetResult()
                if ($null -eq $line) {
                    $session.Process.WaitForExit()
                    throw "Flutter stopped on $($session.Serial) (exit code $($session.Process.ExitCode))."
                }
                $session.Line = $session.Process.StandardOutput.ReadLineAsync()
                if ($line -notmatch '^\[\{') {
                    if ($line) { Write-Host "[$($session.Serial)] $line" }
                    continue
                }
                foreach ($message in (ConvertFrom-Json -InputObject $line)) {
                    switch ($message.event) {
                        'app.start' { $session.AppId = $message.params.appId }
                        'app.started' {
                            $session.Started = $true
                            Write-Host "Flutter ready on $($session.Serial)." -ForegroundColor Green
                        }
                        'app.log' { Write-Host "[$($session.Serial)] $($message.params.log)" }
                        'app.progress' {
                            if ($message.params.message) {
                                Write-Host "[$($session.Serial)] $($message.params.message)"
                            }
                        }
                        'daemon.logMessage' { Write-Host "[$($session.Serial)] $($message.params.message)" }
                    }
                    if ($message.error) { Write-Host "[$($session.Serial)] $($message.error)" -ForegroundColor Yellow }
                    if ($message.result.message) { Write-Host "[$($session.Serial)] $($message.result.message)" }
                }
            }

            if (-not [Console]::IsInputRedirected -and [Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true).KeyChar
                if ($key -ceq 'q') { break }
                if ($key -in @('r', 'R')) {
                    foreach ($session in ($sessions | Where-Object Started)) {
                        Send-FlutterCommand $session 'app.restart' @{ fullRestart = ($key -ceq 'R'); pause = $false }
                    }
                }
            }
            Start-Sleep -Milliseconds 50
        }
    } finally {
        foreach ($session in $sessions) {
            if ($session.Process.HasExited) { continue }
            try {
                if ($session.AppId) { Send-FlutterCommand $session 'app.stop' @{} }
                else { $session.Process.StandardInput.Close() }
            } catch {
                Write-Host "Flutter was already stopping on $($session.Serial)." -ForegroundColor Yellow
            }
        }
        foreach ($session in $sessions) {
            if (-not $session.Process.WaitForExit(10000)) {
                & taskkill.exe /PID $session.Process.Id /T /F | Out-Null
            }
            $session.Process.Dispose()
        }
    }
}

try {
    Write-Host '=== isme.gg Android development launcher ===' -ForegroundColor Cyan
    $modeCount = @(@($TV, $Mobile, $Both) | Where-Object { $_ }).Count
    if ($modeCount -gt 1) { throw 'Choose only one of -TV, -Mobile (or -Smartphone), or -Both.' }
    if ($Avd -and $Both) { throw 'Use -TvAvd and -MobileAvd to override the two AVD names in -Both mode.' }
    if ($Both) { $targets = @($TvAvd, $MobileAvd) }
    elseif ($Mobile) { $targets = @(if ($Avd) { $Avd } else { $MobileAvd }) }
    else { $targets = @(if ($Avd) { $Avd } else { $TvAvd }) }
    if (@($targets | Select-Object -Unique).Count -ne $targets.Count -or @($targets | Where-Object { -not $_ }).Count) {
        throw 'Provide distinct, non-empty AVD names.'
    }
    Write-Host "Targets: $($targets -join ', ')"
    if ($CheckOnly -and $BuildOnly) { throw 'Choose either -CheckOnly or -BuildOnly.' }
    $git = Find-Tool 'git.exe'
    $localChanges = @(& $git status --porcelain=v1 --untracked-files=no)
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect Git status.' }
    $branch = & $git branch --show-current
    if ($LASTEXITCODE -ne 0) { throw 'Could not determine the current Git branch.' }
    if ($SkipPull -or $localChanges.Count -or $branch -ne 'main') {
        Write-Host '[1/5] Using local code (automatic update requires a clean main checkout).'
    } else {
        Write-Host '[1/5] Updating from GitHub...' -ForegroundColor Cyan
        $launcherPath = $PSCommandPath
        $before = (Get-FileHash -LiteralPath $launcherPath -Algorithm SHA256).Hash
        Invoke-Checked $git @('fetch','origin','main')
        & $git merge-base --is-ancestor HEAD origin/main
        if ($LASTEXITCODE -eq 0) {
            Invoke-Checked $git @('merge','--ff-only','origin/main')
        } elseif ($LASTEXITCODE -eq 1) {
            Write-Host 'Using local main because it has commits outside origin/main.' -ForegroundColor Yellow
        } else {
            throw 'Could not compare local main and origin/main.'
        }
        Invoke-Checked $git @('log','-1','--oneline')
        $after = (Get-FileHash -LiteralPath $launcherPath -Algorithm SHA256).Hash
        if ($before -ne $after) {
            Write-Host 'Launcher updated. Reloading it before the build...' -ForegroundColor Cyan
            $nextArgs = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$launcherPath,'-SkipPull','-TvAvd',$TvAvd,'-MobileAvd',$MobileAvd)
            if ($Avd) { $nextArgs += @('-Avd',$Avd) }
            if ($TV) { $nextArgs += '-TV' }
            if ($Mobile) { $nextArgs += '-Mobile' }
            if ($Both) { $nextArgs += '-Both' }
            if ($ReuseEmulator) { $nextArgs += '-ReuseEmulator' }
            if ($JdkDir) { $nextArgs += @('-JdkDir',$JdkDir) }
            if ($FlutterDir) { $nextArgs += @('-FlutterDir',$FlutterDir) }
            if ($CheckOnly) { $nextArgs += '-CheckOnly' }
            if ($BuildOnly) { $nextArgs += '-BuildOnly' }
            & powershell.exe @nextArgs
            exit $LASTEXITCODE
        }
    }
    $trackedBefore = Get-TrackedState $git

    $toolchain = Get-Content -LiteralPath 'toolchain.json' -Raw | ConvertFrom-Json
    $settings = Get-Content -LiteralPath 'android/settings.gradle' -Raw
    $wrapper = Get-Content -LiteralPath 'android/gradle/wrapper/gradle-wrapper.properties' -Raw
    $appGradle = Get-Content -LiteralPath 'android/app/build.gradle' -Raw
    $gradleProperties = Get-Content -LiteralPath 'android/gradle.properties' -Raw
    if ($settings -notmatch ('id\s+"com\.android\.application"\s+version\s+"' + [regex]::Escape($toolchain.androidGradlePlugin) + '"') -or
        $settings -notmatch ('id\s+"org\.jetbrains\.kotlin\.android"\s+version\s+"' + [regex]::Escape($toolchain.kotlin) + '"') -or
        $wrapper -notmatch ('(?m)^distributionUrl=.*?/gradle-' + [regex]::Escape($toolchain.gradle) + '-(?:bin|all)\.zip\s*$') -or
        $appGradle -notmatch ('(?m)^\s*compileSdk\s+' + $toolchain.androidSdk + '\s*$') -or
        $appGradle -notmatch ('(?m)^\s*buildToolsVersion\s+"' + [regex]::Escape($toolchain.androidBuildTools) + '"\s*$')) {
        throw 'Tracked Android Gradle settings differ from toolchain.json. Fix shared configuration in the repository, not on Windows.'
    }
    foreach ($property in @('android.newDsl', 'android.builtInKotlin')) {
        $escaped = [regex]::Escape($property)
        $definitions = [regex]::Matches($gradleProperties, "(?m)^[ \t]*$escaped(?=[ \t=:]).*")
        if ($definitions.Count -ne 1 -or $definitions[0].Value.Trim() -cne "$property=false") {
            throw "android/gradle.properties must set $property=false once before Flutter runs."
        }
    }
    Write-Host '[2/5] Checking pinned Android and Flutter tools...' -ForegroundColor Cyan
    $sdkCandidates = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME)
    if ($env:LOCALAPPDATA) { $sdkCandidates += (Join-Path $env:LOCALAPPDATA 'Android\Sdk') }
    $sdk = $sdkCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if (-not $sdk) { throw 'Android SDK not found. Configure Android Studio or ANDROID_HOME.' }
    $env:ANDROID_HOME = $sdk
    $env:ANDROID_SDK_ROOT = $sdk
    $env:Path = "$(Join-Path $sdk 'platform-tools');$(Join-Path $sdk 'emulator');$env:Path"
    $flutterCandidates = @()
    if ($env:USERPROFILE) { $flutterCandidates += (Join-Path $env:USERPROFILE 'flutter\bin\flutter.bat') }
    $flutter = Find-PinnedFlutter $FlutterDir $toolchain.flutter $toolchain.dart $flutterCandidates
    $env:Path = "$(Split-Path -Parent $flutter);$env:Path"
    if (-not (Test-Path (Join-Path $sdk "platforms\android-$($toolchain.androidSdk)\android.jar"))) {
        throw "Android SDK Platform $($toolchain.androidSdk) is required. Install it in Android Studio > SDK Manager."
    }
    if (-not (Test-Path (Join-Path $sdk "build-tools\$($toolchain.androidBuildTools)\aapt2.exe"))) {
        throw "Android SDK Build Tools $($toolchain.androidBuildTools) is required. Install it in Android Studio > SDK Manager."
    }
    $jdk = Find-CompatibleJdk $JdkDir $flutter $toolchain.java
    Write-Host "Pinned Flutter $($toolchain.flutter) / Dart $($toolchain.dart) ($flutter)" -ForegroundColor Green
    $env:JAVA_HOME = $jdk
    $env:Path = "$(Join-Path $jdk 'bin');$env:Path"
    Write-Host "Using compatible Java SDK: $jdk" -ForegroundColor Green
    # Flutter otherwise prefers Android Studio's bundled runtime over JAVA_HOME.
    # This intentionally persists the JDK choice in this user's Flutter configuration.
    Invoke-Checked $flutter @('config', "--jdk-dir=$jdk")
    Assert-TrackedState $git $trackedBefore 'after Flutter SDK configuration'
    if ($CheckOnly) {
        Write-Host 'Toolchain and tracked checkout verified.' -ForegroundColor Green
        exit 0
    }
    if (-not $BuildOnly) {
    $adb = Find-Tool 'adb.exe' @((Join-Path $sdk 'platform-tools\adb.exe'))
    $emulator = Find-Tool 'emulator.exe' @((Join-Path $sdk 'emulator\emulator.exe'))
    Invoke-Checked $adb @('start-server')
    $avds = @(& $emulator -list-avds)
    if ($LASTEXITCODE -ne 0) { throw 'Could not list installed AVDs.' }
    $missingAvds = @($targets | Where-Object { $_ -notin $avds })
    if ($missingAvds.Count) {
        Write-Host "Available AVDs: $($avds -join ', ')"
        throw "AVD(s) not found: $($missingAvds -join ', '). Create the missing emulator(s) in Android Studio or pass the corresponding AVD override."
    }

    Write-Host '[3/5] Starting selected Android emulator(s)...' -ForegroundColor Cyan
    $serials = @()
    foreach ($target in $targets) {
        $serials += (Start-SelectedAvd -Avd $target -Adb $adb -Emulator $emulator -ReuseEmulator ([bool]$ReuseEmulator))
    }
    if (@($serials | Select-Object -Unique).Count -ne $targets.Count) {
        throw 'The selected AVDs did not resolve to distinct devices.'
    }

    } else {
        Write-Host '[3/5] Build-only mode: skipping emulators.'
    }

    Write-Host '[4/5] Preparing Gradle and Flutter dependencies...' -ForegroundColor Cyan
    $wrapperStamp = 'android\.gradle\isme-wrapper-sdk.txt'
    $wrapperIdentity = "$($toolchain.flutter)|$($toolchain.gradle)"
    $preparedIdentity = if (Test-Path -LiteralPath $wrapperStamp) {
        (Get-Content -LiteralPath $wrapperStamp -Raw).Trim()
    } else { '' }
    if ($preparedIdentity -ne $wrapperIdentity -or
        -not (Test-Path 'android\gradlew.bat') -or
        -not (Test-Path 'android\gradle\wrapper\gradle-wrapper.jar')) {
        & (Join-Path $PSScriptRoot 'prepare-windows.ps1') -Flutter $flutter
        New-Item -ItemType Directory -Force -Path 'android\.gradle' | Out-Null
        Set-Content -LiteralPath $wrapperStamp -Value $wrapperIdentity -Encoding ASCII
    }
    Assert-TrackedState $git $trackedBefore 'after Gradle wrapper preparation'
    $dart = Join-Path (Split-Path -Parent $flutter) 'dart.bat'
    Invoke-Checked $dart @('tools/prepare_fonts.dart')
    if (Test-Path -LiteralPath 'pubspec.lock') {
        $trackedLock = @(& $git ls-files -- pubspec.lock)
        if ($LASTEXITCODE -ne 0) { throw 'Could not check dependency lockfile.' }
        if ($trackedLock.Count -gt 0) { Invoke-Checked $flutter @('pub','get','--enforce-lockfile') }
        else { Invoke-Checked $flutter @('pub','get') }
    } else { Invoke-Checked $flutter @('pub','get') }
    Assert-TrackedState $git $trackedBefore 'after dependencies'
    $debugApk = 'build/app/outputs/flutter-apk/app-debug.apk'
    if ($BuildOnly -or $Both) {
        # Flutter otherwise runs one Gradle build per device against the same
        # project caches. Build once and let Flutter install the APK on both.
        Write-Host '[5/5] Building the shared debug APK...' -ForegroundColor Cyan
        Invoke-Checked $flutter @('build','apk','--debug','--no-pub','--target-platform','android-arm,android-arm64,android-x64')
        Assert-TrackedState $git $trackedBefore 'after debug build'
    }
    if ($BuildOnly) {
        Write-Host 'Build complete. The build preserved tracked files.' -ForegroundColor Green
        exit 0
    }

    # Guard build configuration while allowing Dart edits for hot reload.
    $sessionPaths = @('android', 'analysis_options.yaml', 'pubspec.yaml', 'pubspec.lock', 'toolchain.json')
    $trackedBefore = Get-TrackedState $git $sessionPaths
    Write-Host '[5/5] Launching isme.gg with Flutter...' -ForegroundColor Cyan
    Write-Host 'Keep this window open for hot reload: r = reload, R = restart, q = quit.'
    if ($Both) {
        Write-Host "Running on both selected emulators: $($serials -join ', ')" -ForegroundColor Green
        Write-Host 'Hot reload/restart applies to both devices in this terminal.'
        Invoke-BothFlutterRuns -Flutter $flutter -Serials $serials -Apk $debugApk
    } else {
        Invoke-Checked $flutter @('run','--debug','--no-pub','-d',$serials[0])
    }
    Assert-TrackedState $git $trackedBefore 'after Flutter run' $sessionPaths
    Write-Host 'The development session preserved tracked build configuration.' -ForegroundColor Green
    exit 0
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($null -ne $trackedBefore) {
        try { Assert-TrackedState $git $trackedBefore 'failure diagnostics' $sessionPaths }
        catch { Write-Host $_.Exception.Message -ForegroundColor Yellow }
    }
    exit 1
}
