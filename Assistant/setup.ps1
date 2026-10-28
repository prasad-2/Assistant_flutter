# Windows setup. Run via setup.bat (or: powershell -ExecutionPolicy Bypass -File setup.ps1)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Flutter not found in PATH. Install Flutter and reopen the terminal."
}

# 1. back up our sources (flutter create must not overwrite them)
$tmp = Join-Path $env:TEMP ("mft_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
Copy-Item lib, pubspec.yaml, analysis_options.yaml, android_patch -Destination $tmp -Recurse

# 2. generate platform folders
flutter create --org com.personal --project-name my_finance_todo --platforms android .
if ($LASTEXITCODE -ne 0) { throw "flutter create failed" }

# 3. restore our sources
Remove-Item lib -Recurse -Force
Copy-Item "$tmp\lib" lib -Recurse
Copy-Item "$tmp\pubspec.yaml" pubspec.yaml -Force
Copy-Item "$tmp\analysis_options.yaml" analysis_options.yaml -Force
if (Test-Path test) { Remove-Item test -Recurse -Force }

# 4. Android manifest + MainActivity (FlutterFragmentActivity for local_auth)
Copy-Item android_patch\AndroidManifest.xml android\app\src\main\AndroidManifest.xml -Force
$kdir = "android\app\src\main\kotlin\com\personal\my_finance_todo"
New-Item -ItemType Directory -Force -Path $kdir | Out-Null
Copy-Item android_patch\MainActivity.kt "$kdir\MainActivity.kt" -Force

# 5. Gradle: minSdk 24 + core library desugaring
$utf8 = New-Object System.Text.UTF8Encoding($false)
$kts = "android\app\build.gradle.kts"
$grv = "android\app\build.gradle"
if (Test-Path $kts) {
    $s = [IO.File]::ReadAllText((Resolve-Path $kts))
    if ($s -notmatch "isCoreLibraryDesugaringEnabled") {
        $s = ([regex]'compileOptions\s*\{').Replace($s, "compileOptions {`n        isCoreLibraryDesugaringEnabled = true", 1)
        $s += "`ndependencies {`n    coreLibraryDesugaring(`"com.android.tools:desugar_jdk_libs:2.1.4`")`n}`n"
    }
    $s = $s -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24'
    [IO.File]::WriteAllText((Resolve-Path $kts), $s, $utf8)
} elseif (Test-Path $grv) {
    $s = [IO.File]::ReadAllText((Resolve-Path $grv))
    if ($s -notmatch "coreLibraryDesugaringEnabled") {
        $s = ([regex]'compileOptions\s*\{').Replace($s, "compileOptions {`n        coreLibraryDesugaringEnabled true", 1)
        $s += "`ndependencies {`n    coreLibraryDesugaring `"com.android.tools:desugar_jdk_libs:2.1.4`"`n}`n"
    }
    $s = $s -replace 'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 24'
    [IO.File]::WriteAllText((Resolve-Path $grv), $s, $utf8)
} else {
    Write-Warning "build.gradle not found - patch Gradle manually (see README)."
}

flutter pub get
Write-Host "`nDone. Connect your phone (USB debugging on) and run: flutter run" -ForegroundColor Green
