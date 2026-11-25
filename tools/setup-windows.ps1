param(
    [string]$Avd = 'ismegg_TV_API_36',
    [switch]$SkipPull
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

try {
    Write-Host '=== isme.gg Android development launcher ===' -ForegroundColor Cyan
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
            $dirty | Write-Host
            throw 'Tracked local changes found. Commit or stash them deliberately, then rerun. To test your local changes without pulling, use setupwindows.bat -SkipPull.'
        }
        Invoke-Checked $git @('pull','--ff-only','--no-rebase','--no-autostash','origin','main')
        Invoke-Checked $git @('log','-1','--oneline')
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
    if ($env:USERPROFILE) { $flutterCandidates += (Join-Path $env:USERPROFILE 'flutter\bin\flutter.bat') }
    $flutter = Find-Tool 'flutter.bat' $flutterCandidates
    $adb = Find-Tool 'adb.exe' @((Join-Path $sdk 'platform-tools\adb.exe'))
    $emulator = Find-Tool 'emulator.exe' @((Join-Path $sdk 'emulator\emulator.exe'))
    $env:Path = "$(Split-Path -Parent $flutter);$env:Path"
    if (-not (Test-Path (Join-Path $sdk 'platforms\android-36\android.jar'))) {
        throw 'Android SDK Platform 36 is required by the current app. Install it in Android Studio > SDK Manager.'
    }
    Invoke-Checked $adb @('start-server')
    $avds = @(& $emulator -list-avds)
    if ($LASTEXITCODE -ne 0 -or $avds -notcontains $Avd) {
        Write-Host "Available AVDs: $($avds -join ', ')"
        throw "AVD '$Avd' not found. Create it in Android Studio or pass -Avd NAME."
    }

    Write-Host '[3/5] Starting or reusing Android TV emulator...' -ForegroundColor Cyan
    $serial = Find-AvdSerial $adb $Avd
    if (-not $serial) {
        # Avoid duplicate launches when the AVD is already starting but ADB is offline.
        $escaped = [regex]::Escape($Avd)
        $running = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '^(emulator|qemu-system-.+)\.exe$' -and
                $_.CommandLine -match "(?i)(?:-avd\s+|@|\\avd\\)\x22?$escaped(?:\x22|\s|\.avd|$)"
            })
        if ($running.Count -eq 0) {
            Start-Process -FilePath $emulator -ArgumentList @('-avd', $Avd)
        } else {
            Write-Host 'Matching emulator is already starting.'
        }
        $deadline = (Get-Date).AddMinutes(5)
        do {
            Start-Sleep -Seconds 2
            $serial = Find-AvdSerial $adb $Avd
        } until ($serial -or (Get-Date) -ge $deadline)
        if (-not $serial) { throw 'Emulator did not connect to ADB within five minutes.' }
    }
    $deadline = (Get-Date).AddMinutes(5)
    do {
        $boot = @(& $adb -s $serial shell getprop sys.boot_completed 2>$null)
        if ($LASTEXITCODE -eq 0 -and ($boot -join '').Trim() -eq '1') { break }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    if (($boot -join '').Trim() -ne '1') { throw 'Android did not complete boot within five minutes.' }
    Write-Host "Android TV ready: $serial"

    Write-Host '[4/5] Preparing Gradle and Flutter dependencies...' -ForegroundColor Cyan
    if (-not (Test-Path 'android\gradlew.bat') -or
        -not (Test-Path 'android\gradle\wrapper\gradle-wrapper.jar')) {
        & (Join-Path $PSScriptRoot 'prepare-windows.ps1')
    }
    Invoke-Checked $flutter @('pub','get')

    Write-Host '[5/5] Building, installing and launching isme.gg...' -ForegroundColor Cyan
    Write-Host 'Keep this window open for hot reload: r = reload, R = restart, q = quit.'
    Invoke-Checked $flutter @('run','--debug','-d',$serial)
    exit 0
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
