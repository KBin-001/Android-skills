# 开机 Logo / 充电动画 / 系统级显示定制

> 分层：MTK 平台规则（BootLoader 阶段 + 系统级配置）

## 1. 移除开机模式字符（LK2）[已验证]

设备开机早期屏幕左上角打印的 `=> NORMAL MODE / RECOVERY MODE / POWER OFF CHARGING MODE` 等字符，来自 **LK2 Bootloader 阶段**，不是 Android Framework。

路径：`mediatek/proprietary/bootable/bootloader/lk2/app/mt_boot/mt_boot.c`，函数 `show_boot_mode()`。

**关键**：不是注释字符串那么简单，而是直接 `return` 退出函数，让后续显示逻辑走不到：

```c
case NORMAL_BOOT:
    // n = snprintf(str_buf, BUF_LEN, " => NORMAL MODE\n");
    return;          // 提前退出，后续显示代码不执行
    break;
```

量产版本通常移除（研发阶段保留有调试价值）。

## 2. 关机充电动画（KPOC）定制 [已验证]

- 完整流程与异常排查见 `references/kpoc-charging.md`。
- 核心：Logo 资源索引 = 代码与资源包之间的 ABI；100% 整图与 1-99% 动态合成是两种绘制模型。
- 新增动画帧/数字/百分号资源时，**必须同步更新代码中的索引宏**。

## 3. 平台级显示定制速查 [已验证]

| 需求 | 修改位置 |
|---|---|
| 物理旋转 180° | `MTK_LCM_PHYSICAL_ROTATION`（VendorConfig.mk） |
| DPI | `ro.sf.lcd_density`（device.mk） |
| 物理尺寸 | `PHYSICAL_WIDTH_MM/HEIGHT_MM`（vendor + kernel） |
| 最低亮度 | `config_screenBrightnessSettingMinimumFloat`（FrameworkResOverlay config.xml，0.0→0.1） |
| 色彩饱和度/色温 | panel init vendor 寄存器（见 panel-init-regs.md） |
| 动态刷新率 | `vfp_low_power` + lcm-params mode-list（见 dsi-timing.md） |
| 开机字符移除 | LK2 `show_boot_mode()` return |

## 4. 修改最低亮度 [已验证]

现象：背光进度条 0% 时几乎全黑。修改 Android 允许的最低亮度：

```xml
<!-- FrameworkResOverlay/res/values/config.xml -->
<item name="config_screenBrightnessSettingMinimumFloat" format="float" type="dimen">0.1</item>
```

> 注意区分：这是**上层允许的最低亮度**；`leds-mtk.c` 的 `brightness_remap_highlight` 是**亮度曲线**（见 backlight-pwm.md）。
