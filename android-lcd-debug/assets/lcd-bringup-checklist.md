# LCD Panel Bring-up 速查模板

> 用途：合入新 panel 时逐项填写核对。状态标记：`[已验证]` 为项目实测值，新 panel 列为空白待填。

## 1. 硬件信息表

| 项 | 参考项目 (LMIBE127119272) [已验证] | 参考项目 (JT132WQL018) [已验证] | 新 Panel |
|---|---|---|---|
| 分辨率 | 1200x1920 类 (DSI VDO) | 1600x2400 (DSI VDO) | |
| DSI 格式 | — | RGB888 | |
| Lane 数 | — | — | |
| VDDIO 1.8V | MT6366 VIBR LDO | — | |
| 偏压 IC | AW37503/OCP2138 (I2C9, 0x3E, ±5.8V) | — | |
| AVDD_EN | GPIO103 | — | |
| AVEE_EN | GPIO150 | — | |
| LCD Reset | GPIO85 | — | |
| TP Reset | GPIO152 | — | |
| 背光 PWM | — | GPIO84 (DISP_PWM, 25.4kHz) | |
| 背光 EN | — | GPIO12 (LCM_LED_EN) | |

## 2. Timing 参数表（来自 datasheet）

| 参数 | 值 | 备注 |
|---|---|---|
| HAC | | |
| HFP / HSA / HBP | | |
| VAC | | |
| VFP / VSA / VBP | | |
| 刷新率 | | |
| PCLK (计算) | | 用 scripts/dsi_timing_calc.py |

## 3. 检查清单（每项必须核对）

**电源与偏压**
- [ ] VDDIO 1.8V 来源：GPIO / PMIC LDO / 固定电源
- [ ] 偏压 IC 型号（BOM 实际型号，参考代码可能不同）
- [ ] 偏压 I2C 控制器 + pinmux（原理图网络，不能按芯片型号推断）
- [ ] 7-bit I2C 地址（逻辑分析仪 8-bit 显示需转换）
- [ ] AVDD/AVEE 寄存器地址 + 电压编码
- [ ] LK2 与 Kernel 电源/总线/地址/GPIO 对照一致
- [ ] 上电顺序：1.8V → 偏压 → Reset → DSI init

**DSI / Panel**
- [ ] 分辨率、lane 数、format、mode-flags
- [ ] init sequence（注意 0x39 packet type、页切换命令顺序）
- [ ] 色彩/色温参数合入位置（锁寄存器前、Sleep Out/Display On 前）
- [ ] 刷新率模式列表（多刷新率时与驱动一致）

**背光**
- [ ] PWM 引脚 pinmux 正确（非普通 GPIO）
- [ ] 背光 EN 引脚独立确认
- [ ] `pwms` period 正确（频率）
- [ ] 唤醒后亮度恢复链路（AAL 恢复坑）

**上层配置**
- [ ] 物理尺寸（PHYSICAL_WIDTH/HEIGHT_MM）
- [ ] DPI（ro.sf.lcd_density）
- [ ] 方向（MTK_LCM_PHYSICAL_ROTATION）
- [ ] 充电动画 Logo 索引（若需 KPOC）

## 4. 验证顺序

1. LK2 Logo 显示
2. Kernel 接管（无闪烁/黑屏跳变）
3. 亮屏/灭屏/唤醒（背光三层状态）
4. 亮度调节全程
5. 刷新率切换（若有）
6. 休眠唤醒重复 10 次
7. 冷启动/重启
