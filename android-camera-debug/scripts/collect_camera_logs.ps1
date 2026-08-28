# Android Camera Debug — 日志采集脚本 (PowerShell)
# 用途：一键采集 kernel dmesg + Camera HAL logcat 的关键日志（找第一有效异常）。
# 用法：.\collect_camera_logs.ps1 [-Sensor gc08a8_mipi_raw] [-OutDir .\logs]
# 依赖：adb 在 PATH 中，设备已连接并 adb root。
param(
  [string]$Sensor = "",
  [string]$OutDir = ".\camera_logs"
)

$ErrorActionPreference = "Stop"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

# 可选：先清空 logcat 再复现（建议交互时手动触发问题）
Write-Host "== 1/3 采集 kernel dmesg =="
$dmesg = adb shell dmesg 2>$null | Out-String
$dmesg | Set-Content "$OutDir\dmesg_$stamp.txt" -Encoding UTF8
if ($Sensor) {
  ($dmesg -split "`n") | Where-Object { $_ -match $Sensor -or $_ -match "imgsensor|sensor_id|ERROR_SENSOR_CONNECT_FAIL|mclk|regulator|cam_pwr" } |
    Set-Content "$OutDir\dmesg_camera_$stamp.txt" -Encoding UTF8
}

Write-Host "== 2/3 采集 Camera HAL logcat =="
$logcat = adb logcat -d -v threadtime 2>$null | Out-String
$logcat | Set-Content "$OutDir\logcat_full_$stamp.txt" -Encoding UTF8
($logcat -split "`n") | Where-Object { $_ -match "mtkcam|camera|$Sensor|configureStreams|metadata|tuning|IdxMgr|ISP_mapping|ISP_param" } |
  Set-Content "$OutDir\logcat_camera_$stamp.txt" -Encoding UTF8

Write-Host "== 3/3 采集电源/模块状态 =="
$reg = adb shell "cat /sys/kernel/debug/regulator/regulator_summary" 2>$null | Out-String
$reg | Set-Content "$OutDir\regulator_summary_$stamp.txt" -Encoding UTF8
$mod = adb shell "cat /proc/modules" 2>$null | Out-String
$mod | Set-Content "$OutDir\modules_$stamp.txt" -Encoding UTF8
$gpio = adb shell "cat /proc/mtk_gpio/soc.pinctrl" 2>$null | Out-String
$gpio | Set-Content "$OutDir\gpio_$stamp.txt" -Encoding UTF8

Write-Host ""
Write-Host "采集完成 → $OutDir"
Write-Host "下一步：打开 dmesg_camera_$stamp.txt / logcat_camera_$stamp.txt，"
Write-Host "寻找【第一有效异常】（第一次 fallback/拒绝/失败），参考 references/log-analysis.md。"
