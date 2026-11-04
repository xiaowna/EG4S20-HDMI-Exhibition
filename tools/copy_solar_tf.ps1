[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[D-Zd-z]:?$')]
    [string]$Drive
)
$ErrorActionPreference = 'Stop'
$taskLetter = $Drive.Substring(0,1).ToUpperInvariant() + ':'
$taskVolume = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$taskLetter'"
if (!$taskVolume -or $taskVolume.DriveType -ne 2) { throw '目标必须是已连接的可移动 TF 卡盘符。未写入任何文件。' }
if ($taskVolume.FileSystem -ne 'FAT32') { throw '开发板要求 FAT32；本脚本不会格式化磁盘。' }
# Read-only filesystem check. Never repair or write into an unhealthy volume.
$taskDiskCheck = & chkdsk $taskLetter 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    Write-Host $taskDiskCheck
    throw 'TF卡文件系统检查未通过。请先备份并处理磁盘错误；未开始复制，也未执行修复或格式化。'
}
$taskRoot = $taskLetter + '\'
$taskSource = Join-Path $PSScriptRoot 'TF卡内容'
$taskManifestPath = Join-Path $PSScriptRoot '媒体校验清单.json'
if (!(Test-Path -LiteralPath $taskSource) -or !(Test-Path -LiteralPath $taskManifestPath)) {
    throw '请从完整的太阳系特展交付包运行脚本。'
}
$taskFiles = @((Get-Content -LiteralPath $taskManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json).files)
if ($taskFiles.Count -ne 29) { throw '素材清单应包含24张BMP、4首WAV及1份署名文件。' }
$taskExpectedNames = @((1..24 | ForEach-Object { '{0:D2}.BMP' -f $_ })) + @((1..4 | ForEach-Object { 'MUSIC{0}.WAV' -f $_ })) + @('CREDITS.TXT')
if (($taskFiles.name -join '|') -cne ($taskExpectedNames -join '|')) {
    throw '素材清单的文件名或顺序错误。应为01至24、MUSIC1至4、CREDITS；未开始复制。'
}
$taskExisting = @(Get-ChildItem -LiteralPath $taskRoot -File -Force | Where-Object { $_.Extension -match '^\.(BMP|WAV)$' })
if ($taskExisting.Count -gt 0) {
    throw '卡根目录已有BMP/WAV。请先备份并自行移出旧素材，再重新运行，以保证专题扫描顺序。脚本不会删除旧文件。'
}
$taskBytes = 0L
foreach ($taskEntry in $taskFiles) {
    if ($taskEntry.name -notmatch '^(?:\d{2}\.BMP|MUSIC[1-4]\.WAV|CREDITS\.TXT)$') { throw '素材清单含不允许的文件名。' }
    $taskPath = Join-Path $taskSource $taskEntry.name
    if (!(Test-Path -LiteralPath $taskPath -PathType Leaf)) { throw "缺少素材：$($taskEntry.name)" }
    if ((Get-FileHash -LiteralPath $taskPath -Algorithm SHA256).Hash -ne $taskEntry.sha256) { throw "素材校验不匹配：$($taskEntry.name)" }
    if (Test-Path -LiteralPath (Join-Path $taskRoot $taskEntry.name)) { throw "目标已有同名文件：$($taskEntry.name)，未开始复制。" }
    $taskBytes += (Get-Item -LiteralPath $taskPath).Length
}
if ([long]$taskVolume.FreeSpace -lt $taskBytes + 1048576) { throw 'TF卡剩余空间不足。' }
# The manifest order is explicit: 01..24, MUSIC1..4, then credits.
# Each Copy-Item completes before the next file creates its FAT entry.
foreach ($taskEntry in $taskFiles) {
    $taskFrom = Join-Path $taskSource $taskEntry.name
    $taskTo = Join-Path $taskRoot $taskEntry.name
    Copy-Item -LiteralPath $taskFrom -Destination $taskTo -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $taskTo -Algorithm SHA256).Hash -ne $taskEntry.sha256) { throw "写入后校验失败：$($taskEntry.name)" }
    Write-Host ('已复制并核对：' + $taskEntry.name)
}
Write-Host '29个文件复制并校验完成。请使用Windows安全移除，再将TF卡插入开发板。'
