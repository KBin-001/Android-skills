# 分辨率 / DPI / 方向 / 刷新率配置

> 分层：通用 Android/MTK 配置 + 已验证项目案例

## 1. 修改物理分辨率（PHYSICAL_WIDTH/HEIGHT）[已验证]

物理尺寸影响系统计算 DPI 与显示比例：

**vendor（LK/用户空间侧）**：

```c
#define PHYSICAL_WIDTH_MM    (172)
#define PHYSICAL_HEIGHT_MM   (258)
params->physical_width  = PHYSICAL_WIDTH_MM;
params->physical_height = PHYSICAL_HEIGHT_MM;
```

**kernel**：

```c
#define PHYSICAL_WIDTH_MM   172
#define PHYSICAL_HEIGHT_MM  258
#define PHYSICAL_WIDTH_UM   (PHYSICAL_WIDTH_MM * 1000)
#define PHYSICAL_HEIGHT_UM  (PHYSICAL_HEIGHT_MM * 1000)
connector->display_info.width_mm  = PHYSICAL_WIDTH_MM;
connector->display_info.height_mm = PHYSICAL_HEIGHT_MM;
```

> ⚠️ 修改后需检查系统计算出的 DPI 是否异常、触摸坐标映射、截图/录屏比例。

## 2. 修改 DPI（ro.sf.lcd_density）[已验证]

**用途**：系统逻辑密度，控制 UI 缩放（不是屏幕真实 DPI）。

```makefile
# device.mk
PRODUCT_PROPERTY_OVERRIDES += ro.sf.lcd_density=320
```

换算公式：`px = dp × dpi / 160`。常见档位：160=mdpi, 240=hdpi, 320=xhdpi, 480=xxhdpi, 640=xxxhdpi。

**影响**：字体/图标/状态栏/导航栏/Launcher/App 布局；App 按 density 加载资源。

**不会影响**：LCD 真实分辨率、timing、TP 触摸坐标、FrameBuffer 分辨率。

**验证**：

```bash
adb shell getprop ro.sf.lcd_density
adb shell wm density          # 若存在 Override density 先 wm density reset
adb shell dumpsys display | grep -i density
```

**风险**：DPI 大幅下降后 UI 变小、字体可读性差、部分 App 布局异常；可试中间值 360/400/420。

## 3. 方向旋转 180°（MTK_LCM_PHYSICAL_ROTATION）[已验证]

```makefile
# VendorConfig.mk
MTK_LCM_PHYSICAL_ROTATION = 180   # 或 0
```

修改面板物理旋转角度。改完需验证：开机方向、重力感应方向、前摄方向、TP 坐标映射。

## 4. DSI 动态刷新率 [已验证]

见 `references/dsi-timing.md`。核心：PCLK 不变，调整 VFP 改变 Vtotal 实现多刷新率；`lcm-params-dsi-mode-list` 与 panel 驱动 mode 配置一致。

## 5. 相关命令速查 [已验证]

```bash
# 查看当前显示信息
adb shell dumpsys display | grep -Ei "density|resolution|orientation"
adb shell wm size
adb shell wm density
adb shell getprop ro.sf.lcd_density
# 强制重置
adb shell wm size reset
adb shell wm density reset
```
