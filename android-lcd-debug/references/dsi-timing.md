# DSI 时序（Timing）计算与动态刷新率

> 分层：通用 DRM/DSI 规则 + 已验证案例（JT132WQL018 90Hz/45Hz 动态刷新率）

## 1. Timing 参数定义 [已验证]

以 `1600x2400` 面板为例（HAC=水平有效，HFP=水平前肩等）：

```text
HAC 1600    // 水平有效像素
HFP 60      // 水平前肩 (front porch)
HSA 20      // 水平同步 (sync)
HBP 40      // 水平后肩 (back porch)
VAC 2400    // 垂直有效像素
VFP 270     // 垂直前肩
VSA 8       // 垂直同步
VBP 38      // 垂直后肩
```

## 2. 核心计算公式 [已验证]

```text
Htotal = HAC + HFP + HSA + HBP
Vtotal = VAC + VFP + VSA + VBP
PCLK   = Htotal × Vtotal × 刷新率
Vtotal_新Hz = PCLK / (Htotal × 新刷新率)
VFP_新Hz    = Vtotal_新Hz - VAC - VSA - VBP
```

### 例：90Hz → 45Hz 动态刷新率 [已验证]

```text
Htotal = 1600+60+20+40 = 1720
Vtotal = 2400+270+8+38 = 2716
PCLK   = 1720 × 2716 × 90 ≈ 421 MHz

45Hz: Vtotal_45 = 421e6 / (1720×45) = 5432 行
      VFP_45   = 5432 - 2400 - 8 - 38 = 2986
```

### 对应 kernel panel 参数修改 [已验证]

```c
static struct mtk_panel_params ext_params = {
    .pll_clk = 485,
    .data_rate = 485 * 2,
    .vfp_low_power = 2986,          // 改这里！从 1410 改为 2986
    .wait_sof_before_dec_vfp = 1,
    .vdo_per_frame_lp_enable = 1,   // 确保是 1
    ...
};
```

## 3. 动态刷新率排查要点 [已验证/待验证]

- 动态刷新率（LTPO/VRR 类）通过调整 VFP 保持 PCLK 不变、改变 Vtotal 实现。
- 关键：`vfp_low_power` 必须与计算值一致；`vdo_per_frame_lp_enable = 1`。
- 改完刷新率要验证：实际 fps、功耗、画面撕裂（tearing）、触控采样率联动。
- `lcm-params-dsi-mode-list`（DTS 侧）与 panel 驱动的 mode 配置必须一致。

## 4. 时序错误的现象 [待验证/通用]

| 现象 | 可能原因 |
|---|---|
| 花屏/条纹 | lane 数或 format 错误、PCLK 过低、bit order 错 |
| 画面偏移/错位 | HSA/HBP/VSA/VBP 与 datasheet 不符 |
| 刷新率不符 | PCLK 或 Vtotal 计算错误、mode-list 与驱动不一致 |
| 低刷新率花屏 | vfp_low_power 计算错误、LPM 时序不满足 |

> 使用 `scripts/dsi_timing_calc.py` 可自动计算 Htotal/Vtotal/PCLK/新刷新率所需 VFP。

## 5. PWM 周期相关（背光侧，另见 backlight-pwm.md）[已验证]

```text
PWM 频率 = 1 / period_ns
例：period 39385 ns → 25.39 kHz
```

period 是 PWM 周期，不是亮度值；亮度由 duty（占空比）决定。
