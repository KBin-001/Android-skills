---
name: android-lcd-debug
description: >-
  Android/MTK LCD/显示排障与 bring-up 技能（现代 DRM 架构：DRM Panel + mtk_dsi + mediatek_v2；旧 LCM_DRIVER 仅作 Legacy 参考）。当用户报告任何屏幕/显示问题——LCD 不亮、黑屏、花屏、背光不亮/常亮/亮度不可调/息屏唤醒后不亮、PWM 异常、屏供电/偏压（AVDD/AVEE/Bias IC）异常、偏压 I2C 写失败、DSI 初始化命令异常、分辨率/DPI/刷新率设置、DSI 动态刷新率、物理分辨率修改、方向旋转 180°、色彩饱和度/色温、关机充电动画（KPOC）显示异常、开机 Logo 显示、EMR 电磁笔与 TP 互斥、面板 bring-up 合入新 LCM/panel 驱动——或要求分析 kernel DRM/DSI/panel 日志、修改 DTS lcm-params/pinctrl/regulator、检查 panel_init/prepare/enable 时序时，必须使用本技能。按「现象→log→DRM 调用链→DTS/时序配置→寄存器/电源→修改→编译→验证」流程系统排查。
license: Apache-2.0 (LICENSE.txt)
compatibility: Android/MTK (MT6789/MT8781/MT8391 等), Kernel 6.x DRM 架构, DSI VDO/CMD panel; 需要 adb 与代码树访问
metadata:
  author: Kevin
  source: D:\Kevin\笔记总结 + note.kbinx.com 显示笔记 + Linux DRM 开源参考
  verified-cases: LMIBE127119272, JT132WQL018, AW37503/OCP2138 bias, KPOC Z3, DISP_PWM GPIO84
---

# Android LCD Debug (MTK, DRM 架构)

把作者的 LCD/显示调试经验转成可重复执行的排障流程。核心原则：**先分层定位（App→SurfaceFlinger→HWC→DRM→DSI→Panel→硬件），再动手改**。

## 主流程（定制：DRM 调用链 8 步 + 时序优先 + 寄存器优先）

**现象 → log → DRM 调用链 → DTS/时序配置 → 寄存器/电源 → 修改 → 编译 → 验证**

1. **现象** — 记录现象与复现步骤。**先区分「无图 vs 无背光」**：截图正常但屏黑 = 背光问题；强光照射能看到暗图 = 背光；截图也黑 = 上层/DRM 内容问题
2. **Log** — 收集 dmesg（DRM/DSI/panel/PWM/regulator）+ 上层日志，找第一有效异常
3. **DRM 调用链** — 确定问题层：`App → SurfaceFlinger → HWC → MTK DRM (mtk_dsi) → DSI → Panel`；或 LK2 早期阶段（Logo 前）
4. **DTS/时序配置** — 核对 lcm-params（resolution/lanes/format/timing）、pinctrl、regulator、GPIO
5. **寄存器/电源** — 时序参数计算（PCLK/Vtotal/VFP）、panel init 寄存器序列、Bias IC 寄存器、PWM 占空比
6. **修改** — 按根因改对应层，先改配置/时序类低成本项
7. **编译** — LK2 与 Kernel 分开编译；**LK2 与 Kernel 配置必须同步**
8. **验证** — 开机 → Logo → Kernel 接管 → 亮屏/灭屏/唤醒 → 亮度调节 → 刷新率 → 休眠恢复

## 快速分诊（现象 → 优先检查层）

| 现象 | 第一怀疑层 | 参考 |
|---|---|---|
| 完全黑屏无背光 | 电源/背光 EN + PWM | references/backlight-pwm.md |
| 有暗图无背光 | PWM duty / LED 层 / 背光 IC | references/backlight-pwm.md |
| 息屏唤醒后不亮 | LED/AAL 恢复链路 | references/backlight-pwm.md |
| 屏完全不亮/无图像 | 供电/偏压/DSI/panel init | references/power-bias.md |
| 偏压 I2C 写失败 | Bias IC 总线/地址/寄存器 | references/power-bias.md |
| 花屏/时序异常 | DSI timing / PCLK / 刷新率 | references/dsi-timing.md |
| 分辨率/DPI/方向不对 | lcm-params + 上层配置 | references/resolution-rotation.md |
| 充电动画显示异常 | Logo 索引/分辨率/旋转 | references/kpoc-charging.md |
| 屏幕色彩不对 | panel vendor 寄存器 | references/panel-init-regs.md |
| 触控/笔干扰 | TP/EMR 联动 | references/tp-emr.md |

## 核心方法论：三层状态模型（背光/亮度类问题通用）

```
Framework logical brightness  ≠  LED driver hw_brightness  ≠  PWM controller duty/波形
```

任何一层都可能显示「非零」，但下一层仍是 0。必须逐层确认，日志要看到**完整的下发链**才算闭环（如 `restore → set hw brightness → pwm_apply`）。

## 显示链路分层（按问题定位）

```text
LK2 (Logo 阶段)          → lcm_init_power/lcm_resume_power + lcm_init_setting[]
App → SurfaceFlinger → HWC → MTK DRM (mtk_dsi.c / mediatek_v2)
  → Panel 驱动 (drm_panel: prepare/enable/disable/unprepare)
    → DSI 命令 (init sequence / vendor regs)
      → 硬件: IO 电源 → 偏压 AVDD/AVEE → GPIO EN → Reset → DSI → 背光 PWM
```

- **Panel 状态**：`prepared/enabled` 表示 LCD 面板状态；**背光由 LED class/PWM 独立链路控制**，两者不是同一个驱动。
- **LK2 与 Kernel 必须对照一致**：电源、GPIO、I2C 总线、地址、电压编码，任何一侧不一致都可能「LK 能亮、Kernel 接管异常」。

## 验证状态标记

- `[已验证]` — 来自已闭环复盘笔记，可直接复用
- `[待验证]` — 推测性/通用结论，使用前必须在目标平台复核

## 使用本技能的注意事项

- **不要跳过分层定位直接改代码**。背光亮只是结果，不是根因定位。
- **不要照搬其他项目的板级配置**（I2C 总线、GPIO、电源归属、时序），必须按原理图 + datasheet 核对。
- **软件日志成功 ≠ 硬件正确**：I2C ACK 只能证明从设备响应，需万用表/示波器实测电压、PWM 波形。
- **现代 MTK 以 DRM Panel + mtk_dsi + mediatek_v2 为主**；旧 `LCM_DRIVER`（`LCM_DRIVER`/`lcm_get_params()`/`push_table()`）只作为 Legacy 参考，不要当作新平台通用规则。
- 找不到根因时回到「第一有效异常」：它通常出现在问题链的第一次 fallback/拒绝处。
- 更多开源参考源码在 `D:\桌面\skills-kb\lcd-reference\`（linux mtk_dsi.c / OPPO lcm-params / LCM_Collection）。
