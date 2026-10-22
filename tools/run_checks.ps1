# 一键检查。用法见 docs/README.md；日志写系统临时目录，测试使用隔离存档。
param([string]$GodotPath = $env:GODOT_EXECUTABLE)
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $command = Get-Command godot -ErrorAction SilentlyContinue
    if ($command) { $GodotPath = $command.Source }
}
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw '找不到 Godot。请使用 -GodotPath 指定 Godot 可执行文件的完整路径。'
}
$logDirectory = Join-Path ([IO.Path]::GetTempPath()) ('will-checks-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $logDirectory | Out-Null

function Invoke-Check([string]$Name, [string]$Extra, [string]$Expected = '') {
    $stdout = Join-Path $logDirectory ($Name + '.out.log')
    $stderr = Join-Path $logDirectory ($Name + '.err.log')
    $arguments = '--headless --path "{0}" {1}' -f $projectPath, $Extra
    $process = Start-Process -FilePath $GodotPath -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $null = $process.Handle # Cache the process handle for ExitCode on Windows PowerShell 5.1.
    if (-not $process.WaitForExit(90000)) {
        # 只停止本脚本启动的测试进程，不干扰用户编辑器或游戏。
        $process.Kill()
        throw "$Name 超时。日志：$logDirectory"
    }
    $process.WaitForExit()
    $output = (Get-Content -LiteralPath $stdout -Raw -Encoding UTF8) + (Get-Content -LiteralPath $stderr -Raw -Encoding UTF8)
    if ($process.ExitCode -ne 0 -or $output -match '(?m)^(SCRIPT ERROR:|ERROR:|FAIL:)' -or ($Expected -ne '' -and $output -notmatch $Expected)) {
        Write-Host $output
        throw "$Name 失败。日志：$logDirectory"
    }
    Write-Host "$Name PASS"
    $output -split "`n" | Where-Object { $_ -match '^(CORE:|FLOW:|DRAG:|FIRST_LEVEL:|ENTRANCE:|CHARACTER_SLIDE:|MULTI_ROW:|QYY_SPINE:)' } | ForEach-Object { Write-Host $_ }
}

Invoke-Check 'import' '--editor --import --quit'
Invoke-Check 'core' 'res://tools/core_regression.tscn' 'CORE: \d+ checks, 0 failures'
Invoke-Check 'flow' 'res://tools/flow_probe.tscn' 'FLOW: \d+ checks, 0 failures'
Invoke-Check 'drag' 'res://tools/drag_preview_probe.tscn' 'DRAG: \d+ checks, 0 failures'
Invoke-Check 'first-level' 'res://tools/first_level_probe.tscn' 'FIRST_LEVEL: 6 checks, 0 failures'
Invoke-Check 'entrance' 'res://tools/entrance_probe.tscn' 'ENTRANCE: \d+ checks, 0 failures'
Invoke-Check 'character-slide' 'res://tools/character_slide_probe.tscn' 'CHARACTER_SLIDE: \d+ checks, 0 failures'
Invoke-Check 'multi-row' 'res://tools/multi_row_probe.tscn' 'MULTI_ROW: \d+ checks, 0 failures'
Invoke-Check 'qyy-spine' 'res://tools/qyy_spine_probe.tscn' 'QYY_SPINE: \d+ checks, 0 failures'
Write-Host "全部通过。完整日志：$logDirectory"
