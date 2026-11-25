param(
    [string]$Avd,
    [switch]$TV,
    [Alias('Smartphone','Phone')][switch]$Mobile,
    [switch]$Both,
    [string]$TvAvd = 'ismegg_TV_API_36',
    [string]$MobileAvd = 'ismegg_Mobile_API_36',
    [switch]$SkipPull,
    [switch]$ReuseEmulator,
    [string]$JdkDir
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

function Find-CompatibleJdk {
    param([string]$Explicit, [string]$Flutter)
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
        if ($versionLine -match '^JAVA_VERSION="(17|21)(?:\.|"|-)') {
            return (Resolve-Path -LiteralPath $jdkHome).Path
        }
    }
    throw 'An installed JDK 17 or 21 is required. Use the official Eclipse Temurin Windows x64 JDK MSI from https://adoptium.net/temurin/releases/?version=21 (no Winget needed), or pass -JdkDir "C:\path\to\jdk-21".'
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

# The multi-device Flutter runner shares one interactive console.
# Refuse other connected Android/custom devices rather than installing blindly.
function Assert-BothTargets {
    param([string]$Adb, [string]$Flutter, [string[]]$Expected)
    foreach ($folder in @('windows','linux','macos','ios')) {
        if ((Test-Path (Join-Path $folder 'CMakeLists.txt')) -or
            (Test-Path (Join-Path $folder 'Runner.xcodeproj'))) {
            throw 'Both mode requires the Android-only Flutter project. Use individual device runs.'
        }
    }
    $listed = @(& $Adb devices)
    if ($LASTEXITCODE -ne 0) { throw 'Could not list ADB devices.' }
    $connected = @()
    foreach ($line in $listed) {
        if ($line -match '^(\S+)\s+device\s*$') { $connected += $Matches[1] }
    }
    $unexpected = @($connected | Where-Object { $_ -notin $Expected })
    $missing = @($Expected | Where-Object { $_ -notin $connected })
    if ($unexpected.Count -or $missing.Count) {
        throw "Both mode needs exactly the selected Android devices. Disconnect other devices ($($unexpected -join ', ')) or reconnect missing devices ($($missing -join ', '))."
    }
    $json = (& $Flutter devices --machine) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'Could not verify Flutter device targets.' }
    $devices = ConvertFrom-Json -InputObject $json
    $other = @($devices | Where-Object {
        $_.id -notin $Expected -and $_.isSupported -ne $false -and
        $_.targetPlatform -notmatch '^(web-|windows-|linux-|darwin-|macos-|fuchsia-)'
    })
    $missingFlutter = @($Expected | Where-Object { $_ -notin $devices.id })
    if ($other.Count -or $missingFlutter.Count) {
        throw "Flutter target verification failed. Other targets: $($other.id -join ', '); missing: $($missingFlutter -join ', '). Use individual device commands if needed."
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
    $git = Find-Tool 'git.exe'
    if (-not $SkipPull) {
        Write-Host '[1/5] Updating from GitHub...' -ForegroundColor Cyan
        $branch = & $git branch --show-current
        if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') {
            throw 'Switch to the main branch before running this launcher.'
        }
        $dirty = @(& $git status --porcelain --untracked-files=no)
        if ($LASTEXITCODE -ne 0) { throw 'Could not inspect Git status.' }
        if ($dirty.Count -gt 0) {
            Write-Host 'Local tracked changes detected. Git will preserve them if the incoming update does not overlap.' -ForegroundColor Yellow
            $dirty | Write-Host
        }
        $launcherPath = $PSCommandPath
        $before = (Get-FileHash -LiteralPath $launcherPath -Algorithm SHA256).Hash
        & $git pull --ff-only --no-rebase --no-autostash origin main
        if ($LASTEXITCODE -ne 0) {
            throw 'Git could not fast-forward safely. Review the Git error above. Local changes are not reset or stashed automatically. Resolve the conflict or run setupwindows.bat -SkipPull to use your current checkout.'
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
            & powershell.exe @nextArgs
            exit $LASTEXITCODE
        }
    } else {
        Write-Host '[1/5] Using current local code (pull skipped).'
    }

    Write-Host '[2/5] Checking Android and Flutter tools...' -ForegroundColor Cyan
    $sdkCandidates = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME)
    if ($env:LOCALAPPDATA) { $sdkCandidates += (Join-Path $env:LOCALAPPDATA 'Android\Sdk') }
    $sdk = $sdkCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if (-not $sdk) { throw 'Android SDK not found. Configure Android Studio or ANDROID_HOME.' }
    $env:ANDROID_HOME = $sdk
    $env:ANDROID_SDK_ROOT = $sdk
    $env:Path = "$(Join-Path $sdk 'platform-tools');$(Join-Path $sdk 'emulator');$env:Path"
    $flutterCandidates = @('C:\flutter\bin\flutter.bat', 'C:\src\flutter\bin\flutter.bat')
    if ($env:FLUTTER_ROOT) { $flutterCandidates += (Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat') }
    if ($env:USERPROFILE) {
        $flutterCandidates += (Join-Path $env:USERPROFILE 'flutter\bin\flutter.bat')
        $flutterCandidates += (Join-Path $env:USERPROFILE 'Documents\ChatGPT\isme.gg\dev-sdk\flutter\bin\flutter.bat')
    }
    $flutter = Find-Tool 'flutter.bat' $flutterCandidates
    $adb = Find-Tool 'adb.exe' @((Join-Path $sdk 'platform-tools\adb.exe'))
    $emulator = Find-Tool 'emulator.exe' @((Join-Path $sdk 'emulator\emulator.exe'))
    $env:Path = "$(Split-Path -Parent $flutter);$env:Path"
    if (-not (Test-Path (Join-Path $sdk 'platforms\android-36\android.jar'))) {
        throw 'Android SDK Platform 36 is required by the current app. Install it in Android Studio > SDK Manager.'
    }
    $jdk = Find-CompatibleJdk $JdkDir $flutter
    $env:JAVA_HOME = $jdk
    $env:Path = "$(Join-Path $jdk 'bin');$env:Path"
    Write-Host "Using compatible Java SDK: $jdk" -ForegroundColor Green
    # Flutter otherwise prefers Android Studio's bundled runtime over JAVA_HOME.
    # This intentionally persists the JDK choice in this user's Flutter configuration.
    Invoke-Checked $flutter @('config', "--jdk-dir=$jdk")
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

    Write-Host '[4/5] Preparing Gradle and Flutter dependencies...' -ForegroundColor Cyan
    if (-not (Test-Path 'android\gradlew.bat') -or
        -not (Test-Path 'android\gradle\wrapper\gradle-wrapper.jar')) {
        & (Join-Path $PSScriptRoot 'prepare-windows.ps1')
    }
    $dart = Join-Path (Split-Path -Parent $flutter) 'dart.bat'
    Invoke-Checked $dart @('tools/prepare_fonts.dart')
    Invoke-Checked $flutter @('pub','get')

    Write-Host '[5/5] Building, installing and launching isme.gg...' -ForegroundColor Cyan
    Write-Host 'Keep this window open for hot reload: r = reload, R = restart, q = quit.'
    if ($Both) {
        Assert-BothTargets -Adb $adb -Flutter $flutter -Expected $serials
        Write-Host "Running on both selected emulators: $($serials -join ', ')" -ForegroundColor Green
        Write-Host 'Hot reload/restart applies to both devices in this terminal.'
        Invoke-Checked $flutter @('run','--debug','-d','all')
    } else {
        Invoke-Checked $flutter @('run','--debug','-d',$serials[0])
    }
    exit 0
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
