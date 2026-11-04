<#
从任意工作目录调用 TD，兼容工程路径中的空格。
示例：powershell -ExecutionPolicy Bypass -File .\tools\run_td.ps1 -Action Check
Check 只做逻辑展开；Build/FixHold/Reports 需完整引脚映射及布线后时序通过。
#>
[CmdletBinding()]
param(
    [ValidateSet('Check', 'Build', 'FixHold', 'Reports')]
    [string]$Action = 'Check',
    [string]$TdExecutable = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$actions = @{
    Check = @('tests/audio_source/check_board.tcl', 'BOARD_AUDIO_SOURCE_ELABORATION_FINISHED')
    Build = @('build_wav_project.tcl', 'BOARD_BUILD_FINISHED')
    FixHold = @('fix_wav_gui_route.tcl', 'GUI_HOLD_FIX_FINISHED')
    Reports = @('refresh_wav_gui_reports.tcl', 'GUI_TIMING_REPORTS_REFRESHED')
}
try {
    $python = Get-Command python -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $checkArguments = @((Join-Path $projectRoot 'tools/prepare_td_project.py'), '--root', $projectRoot, '--relocate')
    if ($Action -eq 'Check') { $checkArguments += '--logic-only' }
    & $python.Source @checkArguments
    if ($LASTEXITCODE -ne 0) { throw "工程预检未通过；$Action 已阻止。" }
    if (!$TdExecutable) {
        $found = Get-Command td_commands_prompt.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $TdExecutable = $found.Source }
        else { $TdExecutable = 'C:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\td_commands_prompt.exe' }
    }
    if (!(Test-Path -LiteralPath $TdExecutable -PathType Leaf)) {
        throw '找不到 TD，请通过 -TdExecutable 指定 td_commands_prompt.exe 的完整路径。'
    }
    $scriptPath = (Join-Path $projectRoot $actions[$Action][0]).Replace('\', '/')
    if ($scriptPath -match '[{}\r\n]') { throw '工程路径不能包含花括号或换行。' }
    $reportDirectory = Join-Path $projectRoot 'reports'
    New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
    $logPath = Join-Path $reportDirectory ('td_' + $Action.ToLowerInvariant() + '_latest.log')
    # TD 启动器会把命令行中的带空格脚本路径拆开；通过标准输入传入完整 Tcl 命令。
    $command = 'if {[catch {source {' + $scriptPath + '}} hdmi_run_error]} {puts stderr "HDMI_RUN_FAILED: $hdmi_run_error"; exit 1}'
    Push-Location -LiteralPath $projectRoot
    $previousPython = $env:HDMI_PROJECT_PYTHON
    try {
        $env:HDMI_PROJECT_PYTHON = $python.Source
        $command | & $TdExecutable 2>&1 | Tee-Object -FilePath $logPath
        $nativeExit = $LASTEXITCODE
    } finally {
        $env:HDMI_PROJECT_PYTHON = $previousPython
        Pop-Location
    }
    $log = Get-Content -LiteralPath $logPath -Raw
    $marker = $actions[$Action][1]
    if ($nativeExit -ne 0 -or $log -match 'HDMI_RUN_FAILED:|(?im)^\s*(?:[A-Z]+-\d+\s*:?\s*)?ERROR\b' -or $log -notmatch ('(?m)^' + [regex]::Escape($marker) + '\s*$')) {
        throw "TD 未成功完成 $Action；请查看 $logPath"
    }
    if ($Action -ne 'Check' -and $log -notmatch '(?m)^HDMI_TIMING_PASSED ') {
        throw "TD 未提供时序通过标记，不能报告构建成功；请查看 $logPath"
    }
    if ($Action -eq 'Check') { Write-Host '仅逻辑展开通过；物理 IO、时序和开发板功能需另行验证。' }
    Write-Host "完成：$Action，日志：$logPath"
} catch {
    Write-Error $_ -ErrorAction Continue
    Write-Warning '本次操作失败。目录中已有的 bit 可能来自上次构建，请勿视为本次成功输出。'
    exit 1
}
