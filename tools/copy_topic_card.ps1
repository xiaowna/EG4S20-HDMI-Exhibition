[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[D-Zd-z]:?$')][string]$Drive,
    [string]$PackageRoot=$PSScriptRoot,
    [switch]$CheckOnly
)
$ErrorActionPreference='Stop'
$taskLetter=$Drive.Substring(0,1).ToUpperInvariant()+':'
$taskVolume=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$taskLetter'"
if (!$taskVolume -or $taskVolume.DriveType -ne 2 -or $taskVolume.FileSystem -ne 'FAT32') {
    throw '目标必须是已连接的可移动FAT32 TF卡；本脚本不格式化磁盘。'
}
$taskDiskCheck=& chkdsk $taskLetter 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { Write-Host $taskDiskCheck; throw '文件系统检查未通过；未写入、修复或格式化。' }
$taskSource=Join-Path $PackageRoot 'TF卡目录版'
$taskManifest=Join-Path $PackageRoot 'TF卡目录版_校验清单.json'
$taskFiles=@((Get-Content -LiteralPath $taskManifest -Raw -Encoding UTF8 | ConvertFrom-Json).files)
$taskExpected=@(1..4 | ForEach-Object { $taskGroup=$_; 1..6 | ForEach-Object { 'TOPIC{0}/{1:D2}.BMP' -f $taskGroup,$_ } })
$taskExpected+=@(1..4 | ForEach-Object { 'MUSIC{0}.WAV' -f $_ })
$taskExpected+=@('CREDITS.TXT')
if ($taskFiles.Count -ne 29 -or ($taskFiles.target -join '|') -cne ($taskExpected -join '|')) { throw '目录版素材清单路径或顺序错误。' }
$taskRoot=$taskLetter+'\'
# Refuse existing image folders, so sequential creation fixes FAT image order.
# Never delete or move old media. Root BMPs may remain: new firmware ignores
# them whenever a TOPIC folder is present; old firmware can still use them.
foreach ($taskGroup in 1..4) {
    $taskFolder=Join-Path $taskRoot ('TOPIC{0}' -f $taskGroup)
    if ((Test-Path -LiteralPath $taskFolder) -and
        @(Get-ChildItem -LiteralPath $taskFolder -File -Force | Where-Object { $_.Extension -ieq '.BMP' }).Count -gt 0) {
        throw "目标专题目录已有图片：$taskFolder。请先自行备份并移出；本脚本不会删除或覆盖。"
    }
}
$taskExtraMusic=@(Get-ChildItem -LiteralPath $taskRoot -File -Force | Where-Object {
    $_.Extension -ieq '.WAV' -and $_.Name -notmatch '^MUSIC[1-4]\.WAV$'
})
if ($taskExtraMusic.Count) { throw '根目录已有其他WAV，会影响曲目顺序；请先自行备份移出。' }
$taskBytes=0L
foreach ($taskEntry in $taskFiles) {
    if ($taskEntry.target -notmatch '^(?:TOPIC[1-4]/0[1-6]\.BMP|MUSIC[1-4]\.WAV|CREDITS\.TXT)$') { throw '不允许的素材路径。' }
    $taskFrom=Join-Path $taskSource $taskEntry.target
    $taskTo=Join-Path $taskRoot $taskEntry.target
    if (!(Test-Path -LiteralPath $taskFrom -PathType Leaf) -or
        (Get-FileHash -LiteralPath $taskFrom -Algorithm SHA256).Hash -ne $taskEntry.sha256) { throw "源素材缺失或校验失败：$($taskEntry.target)" }
    if (Test-Path -LiteralPath $taskTo) {
        if (!(Test-Path -LiteralPath $taskTo -PathType Leaf) -or
            (Get-FileHash -LiteralPath $taskTo -Algorithm SHA256).Hash -ne $taskEntry.sha256) { throw "目标已有不同内容：$taskTo。未开始复制。" }
    } else { $taskBytes+=(Get-Item -LiteralPath $taskFrom).Length }
}
if ([long]$taskVolume.FreeSpace -lt $taskBytes+1048576) { throw 'TF卡剩余空间不足。' }
if ($CheckOnly) { Write-Host '预检通过，未写入文件。'; return }
foreach ($taskEntry in $taskFiles) {
    $taskFrom=Join-Path $taskSource $taskEntry.target
    $taskTo=Join-Path $taskRoot $taskEntry.target
    $taskParent=Split-Path -Parent $taskTo
    if (!(Test-Path -LiteralPath $taskParent)) { New-Item -ItemType Directory -Path $taskParent | Out-Null }
    if (!(Test-Path -LiteralPath $taskTo)) { Copy-Item -LiteralPath $taskFrom -Destination $taskTo }
    if ((Get-FileHash -LiteralPath $taskTo -Algorithm SHA256).Hash -ne $taskEntry.sha256) { throw "写入校验失败：$($taskEntry.target)" }
    Write-Host ('已核对：'+$taskEntry.target)
}
Write-Host '24张图片已分入4个TOPIC文件夹，4首音乐共用根目录。根目录旧BMP保留。'
Write-Host '音乐编号仍按FAT目录顺序；复用既有WAV时保留它们原有顺序。请安全移除TF卡再上板。'
