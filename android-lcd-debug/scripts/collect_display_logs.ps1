# Android LCD Debug — 显示日志采集脚本 (PowerShell)
# 用途：一键采集显示链路相关日志（dmesg DRM/DSI/panel/PWM + SurfaceFlinger/HWC + 显示节点）。
# 用法：.\collect_display_logs.ps1 [-Panel jt132wql018] [-OutDir .\display_logs]
# 依赖：adb 在 PATH 中，设备已连接并 adb root。
param(
  [string]$Panel = "",
  [string]$OutDir = ".\display_logs"
)

$ErrorActionPreference = "Stop"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

Write-Host "== 1/4 采集 kernel dmesg (显示相关) =="
$dmesg = adb shell dmesg 2>$null | Out-String
$dmesg | Set-Content "$OutDir\dmesg_full_$stamp.txt" -Encoding UTF8
$kws = "drm|dsi|panel|pwm|leds|disp_pwm|mtk_dsi|mediatek_v2|regulator|avdd|avee|vibr|backlight|lcd"
if ($Panel) { $kws = "$kws|$Panel" }
($dmesg -split "`n") | Where-Object { $_ -match $kws } |
  Set-Content "$OutDir\dmesg_display_$stamp.txt" -Encoding UTF8

Write-Host "== 2/4 采集 SurfaceFlinger / HWC / 显示服务日志 =="
$sf = adb logcat -d -v threadtime -s SurfaceFlinger:H hwcomposer:D hwcomposer:V 2>$null | Out-String
$sf | Set-Content "$OutDir\logcat_display_$stamp.txt" -Encoding UTF8
$sfFull = adb logcat -d -v threadtime 2>$null | Out-String
($sfFull -split "`n") | Where-Object { $_ -match "SurfaceFlinger|HWComposer|Display|drm|dsi|panel|backlight" } |
  Set-Content "$OutDir\logcat_display_all_$stamp.txt" -Encoding UTF8

Write-Host "== 3/4 采集显示状态节点 =="
adb shell "cat /sys/class/leds/lcd-backlight/max_brightness" 2>$null |
  Set-Content "$OutDir\bl_max_$stamp.txt" -Encoding UTF8
adb shell "cat /sys/class/leds/lcd-backlight/brightness" 2>$null |
  Set-Content "$OutDir\bl_cur_$stamp.txt" -Encoding UTF8
adb shell "cat /sys/kernel/debug/pwm" 2>$null |
  Set-Content "$OutDir\pwm_debug_$stamp.txt" -Encoding UTF8
adb shell "cat /sys/kernel/debug/pinctrl/*/pinmux-pins" 2>$null |
  Set-Content "$OutDir\pinmux_$stamp.txt" -Encoding UTF8
adb shell "cat /sys/kernel/debug/gpio" 2>$null |
  Set-Content "$OutDir\gpio_debug_$stamp.txt" -Encoding UTF8

Write-Host "== 4/4 采集上层显示属性 =="
$props = adb shell "getprop ro.sf.lcd_density; getprop wm" 2>$null | Out-String
$props | Set-Content "$OutDir\display_props_$stamp.txt" -Encoding UTF8
adb shell "dumpsys display" 2>$null |
  Set-Content "$OutDir\dumpsys_display_$stamp.txt" -Encoding UTF8
adb shell "dumpsys SurfaceFlinger" 2>$null |
  Set-Content "$OutDir\dumpsys_sf_$stamp.txt" -Encoding UTF8

Write-Host ""
Write-Host "采集完成 → $OutDir"
Write-Host "下一步：打开 dmesg_display_$stamp.txt，寻找【第一有效异常】；"
Write-Host "背光问题重点核对三层状态: logical brightness → hw_brightness → PWM duty (见 references/backlight-pwm.md)。"
