[CmdletBinding()]
param(
    [string]$GodotPath = '',
    [string]$OutputDirectory = '',
    [switch]$SkipWindows,
    [switch]$SkipAndroid
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $godotCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($null -ne $godotCommand) {
        $GodotPath = $godotCommand.Source
    }
    elseif ($env:LOCALAPPDATA) {
        $GodotPath = Join-Path $env:LOCALAPPDATA 'Programs/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe'
    }
}
if ([string]::IsNullOrWhiteSpace($GodotPath) -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw 'Godot executable was not found. Pass -GodotPath with the path to Godot 4.7.2.'
}
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$toolRoot = Join-Path $projectRoot '.build/tools'
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectRoot 'exports/release'
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$logRoot = Join-Path $projectRoot '.build/export-logs'
New-Item -ItemType Directory -Force -Path $OutputDirectory, $logRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $projectRoot 'exports') | Out-Null
Set-Content -LiteralPath (Join-Path $projectRoot 'exports/.gdignore') -Value '' -Encoding utf8

$savedAppData = $env:APPDATA
$savedJava = $env:JAVA_HOME
$savedAndroid = $env:ANDROID_HOME
try {
    # These editor preferences belong only to this packaging process.
    $env:APPDATA = Join-Path $toolRoot 'godot-config'
    $settingsDirectory = Join-Path $env:APPDATA 'Godot'
    New-Item -ItemType Directory -Force -Path $settingsDirectory | Out-Null
    if (-not $SkipAndroid) {
        $jdk = Get-ChildItem -LiteralPath (Join-Path $toolRoot 'jdk17') -Directory | Select-Object -First 1
        if ($null -eq $jdk) { throw 'Project-local JDK 17 is missing.' }
        $env:JAVA_HOME = $jdk.FullName
        $env:ANDROID_HOME = Join-Path $toolRoot 'android-sdk'
        foreach ($required in @(
            (Join-Path $env:JAVA_HOME 'bin/java.exe'),
            (Join-Path $env:ANDROID_HOME 'platform-tools/adb.exe'),
            (Join-Path $env:ANDROID_HOME 'build-tools/35.0.1/apksigner.bat'),
            (Join-Path $toolRoot 'debug.keystore')
        )) {
            if (-not (Test-Path -LiteralPath $required)) { throw "Export dependency is missing: $required" }
        }
        $javaSetting = $env:JAVA_HOME.Replace('\', '/')
        $androidSetting = $env:ANDROID_HOME.Replace('\', '/')
        @"
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/java_sdk_path="$javaSetting"
export/android/android_sdk_path="$androidSetting"
"@ | Set-Content -LiteralPath (Join-Path $settingsDirectory 'editor_settings-4.7.tres') -Encoding utf8
    }

    & $GodotPath --headless --path $projectRoot --import 2>&1 |
        Tee-Object -FilePath (Join-Path $logRoot 'import.log')
    if ($LASTEXITCODE -ne 0) { throw "Godot import failed with code $LASTEXITCODE" }

    if (-not $SkipWindows) {
        $windowsDirectory = Join-Path $OutputDirectory 'windows'
        New-Item -ItemType Directory -Force -Path $windowsDirectory | Out-Null
        $windowsExe = Join-Path $windowsDirectory 'MoonExcavation.exe'
        & $GodotPath --headless --path $projectRoot --export-release 'Windows Desktop' $windowsExe 2>&1 |
            Tee-Object -FilePath (Join-Path $logRoot 'windows.log')
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $windowsExe)) {
            throw "Windows export failed with code $LASTEXITCODE"
        }
        @'
月面采掘 Demo

解压整个压缩包，双击 MoonExcavation.exe 运行。

WASD 移动，鼠标转视角，长按鼠标左键开采，空格跳跃。
E 打开基地或回舱结算，F 拾取晶石，B / Tab 打开背包。
1 / 2 / 3 切换开采笔刷，Esc 释放鼠标。
进入矿区后按 G，或点右下角“调试”，可以切换触控模式与音效。
V 切换第一 / 第三人称，H 显示操作帮助。
基地内可以选矿区、买装备。试玩进度保存在当前 Windows 用户的 Godot 应用数据目录。

Android 版使用屏幕上的移动、视角、开采和交互控件。
触屏右侧按住开采时，可以同时拖动转向。
'@ | Set-Content -LiteralPath (Join-Path $windowsDirectory 'README.txt') -Encoding utf8
        Compress-Archive -Path (Join-Path $windowsDirectory '*') -DestinationPath (Join-Path $OutputDirectory 'MoonExcavation-Windows-x64.zip') -Force
    }

    if (-not $SkipAndroid) {
        $apkPath = Join-Path $OutputDirectory 'MoonExcavation-Android.apk'
        & $GodotPath --headless --path $projectRoot --export-debug 'Android' $apkPath 2>&1 |
            Tee-Object -FilePath (Join-Path $logRoot 'android.log')
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $apkPath)) {
            throw "Android export failed with code $LASTEXITCODE"
        }
        & (Join-Path $env:ANDROID_HOME 'build-tools/35.0.1/apksigner.bat') verify --verbose --print-certs $apkPath 2>&1 |
            Tee-Object -FilePath (Join-Path $logRoot 'android-signature.log')
        if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
    }

    $releaseFiles = Get-ChildItem -LiteralPath $OutputDirectory -File |
        Where-Object { $_.Extension -in @('.zip', '.apk') }
    $hashes = foreach ($releaseFile in $releaseFiles) {
        $digest = Get-FileHash -LiteralPath $releaseFile.FullName -Algorithm SHA256
        '{0}  {1}' -f $digest.Hash.ToLowerInvariant(), $releaseFile.Name
    }
    $hashes | Set-Content -LiteralPath (Join-Path $OutputDirectory 'SHA256SUMS.txt') -Encoding utf8
    $releaseFiles | Select-Object Name, Length, FullName
}
finally {
    $env:APPDATA = $savedAppData
    $env:JAVA_HOME = $savedJava
    $env:ANDROID_HOME = $savedAndroid
}
