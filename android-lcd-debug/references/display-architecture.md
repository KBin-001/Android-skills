# MTK Display DRM 架构与目录映射

> 分层：通用 DRM 规则 + MTK 平台规则（`[已验证]` 来自项目，`[待验证]` 为通用知识）

## 1. Android 显示完整链路 [已验证/通用]

```text
App
 ↓
SurfaceFlinger (合成)
 ↓
HWC (Hardware Composer)
 ↓
MTK DRM (mtk_dsi.c / mediatek_v2)
 ↓
DSI 控制器 → Panel 驱动 (drm_panel)
 ↓
物理 LCD (含背光、偏压、电源)
```

- 开机早期（Android 未启动）：LK2 负责 Logo，走 `lcm_init_power/lcm_resume_power` + `lcm_init_setting[]`。
- 系统运行期：DRM/KMS 接管，panel 驱动实现 `prepare/enable/disable/unprepare` 生命周期。

## 2. 现代 vs Legacy 架构 [已验证]

| 维度 | 现代 (Kernel 6.x) | Legacy (旧平台) |
|---|---|---|
| 框架 | DRM/KMS：`drm_panel` + `mtk_dsi` + `mediatek_v2` | 旧 LCM：`LCM_DRIVER`/`lcm_get_params()`/`lcm_init()` |
| 注册 | `drm_panel_init` + DTS compatible | `mt65xx_lcm_list.c/.h` |
| DTS | `lcm-params-*` 节点（resolution/lanes/format/mode-flags） | 旧 lcm 节点 |
| 命令发送 | `dcs_write_seq` / `dsi_set_cmdq` | `push_table()` / `dsi_set_cmdq()` |
| 参考 | [linux mtk_dsi.c](https://github.com/torvalds/linux/tree/master/drivers/gpu/drm/mediatek) | [MTK_LCM_Collection](https://github.com/jmpfbmx/MTK_LCM_Collection) |

> 结论：现代平台核心是 `DRM Panel + mtk_dsi + mediatek_v2`；旧 LCM 代码只作 Legacy reference，不要直接照搬为新平台规则。

## 3. 关键代码路径（MTK Kernel 6.x）[已验证/待验证]

| 模块 | 路径（以实际代码树为准） | 职责 |
|---|---|---|
| DSI 控制器 | `drivers/gpu/drm/mediatek/mtk_dsi.c` | DSI 时序、clock、command/video mode |
| Panel 驱动 | `drivers/gpu/drm/panel/panel-<name>-dsi-*.c` | 电源、init 序列、backlight、生命周期 |
| LED/背光 | `drivers/leds/leds-mtk.c` `leds-mtk-pwm.c` `leds-mtk-disp.c` | 亮度映射、PWM 下发 |
| PWM 控制器 | `drivers/pwm/pwm-mtk-disp.c` | 实际 PWM 波形输出 |
| 偏压 IC | 项目自定义驱动或 panel 内嵌 | AVDD/AVEE 电压控制 |
| LK2 LCM | `vendor/mediatek/proprietary/bootable/bootloader/lk2/dev/lcm/<panel>/` | Logo 阶段电源 + init |

## 4. DTS lcm-params 结构（OPPO Kernel 6.12 示例）[待验证/通用]

现代 MTK 用 `lcm-params` 描述 panel 能力（参考 `lcd-reference/oppo-nt37801-lcm-params.dtsi`）：

```dts
lcm-params {
    lcm-params-resolution = <1440 3200>;
    lcm-params-physical-width = <64>;
    lcm-params-physical-height = <129>;
    lcm-params-dsi {
        lcm-params-dsi-density = <560>;
        lcm-params-dsi-lanes = <4>;
        lcm-params-dsi-format = <MTK_MIPI_DSI_FMT_RGB888>;
        lcm-params-dsi-mode-flags = <...>;
        lcm-params-dsi-mode-count = <6>;
        lcm-params-dsi-mode-list = <0 1440 3200 120>, ...;
    };
};
```

- `lcm-params-resolution`：物理分辨率。
- `lcm-params-dsi-lanes/format`：MIPI lane 数与格式。
- `lcm-params-dsi-mode-list`：多刷新率模式的 (index, w, h, fps) 列表，动态刷新率依赖它。
- 物理尺寸（`physical-width/height`）影响系统计算 DPI 与显示效果。

## 5. 新 panel bring-up 快速清单 [已验证/通用]

1. 确认原理图：panel 型号、DSI 接口、lane 数、电源轨（VDDIO/AVDD/AVEE）、背光（PWM/EN 引脚）、Reset GPIO。
2. 确认 panel datasheet：分辨率、timing（HAC/HFP/HSA/HBP/VAC/VFP/VSA/VBP）、DSI 格式、初始化命令序列。
3. 写 panel 驱动（DRM panel）：电源控制 + init 序列 + `prepare/enable/disable/unprepare`。
4. DTS：panel 节点 + lcm-params + pinctrl（含 MIPI pinmux）+ regulator + backlight phandle。
5. LK2 LCM 与 Kernel 同步配置（电源/I2C/GPIO/地址/电压编码）。
6. 编译验证：LK → Logo → Kernel 接管 → 亮屏 → 亮度 → 休眠唤醒。
