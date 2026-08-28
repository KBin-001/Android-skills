# LCD 供电 / 偏压（Power & Bias IC）

> 分层：通用 + MTK 平台规则；核心案例 LMIBE127119272 + AW37503/OCP2138 [已验证]

## 1. 显示电源链路（完整）[已验证]

```text
IO 电源 (VDDIO 1.8V) → 模拟偏压 (AVDD/AVEE) → GPIO Enable → Reset → DSI init → 背光
```

Panel 初始化命令相同只能证明屏规格相同；**板级供电和总线必须重新核对**。

## 2. 偏压 IC 四要素（固定核对）[已验证]

遇到 LCD Bias IC（AW37503/OCP2138 等），核对：

1. **I2C 控制器编号**（原理图网络决定，如 SDA9/SCL9 → I2C9；不能按芯片型号推断）
2. **7-bit Slave Address**（如 `0x3E`；逻辑分析仪可能显示 8-bit `0x7C`，代码仍填 7-bit）
3. **AVDD/AVEE 寄存器地址**（OCP2138: AVDD=Reg0x00, AVEE=Reg0x01）
4. **电压值与寄存器编码**（+5.8V/-5.8V → `0x12`）

示例（已验证）：

```text
I2C9, slave 0x3E, Reg0x00 = 0x12 → AVDD +5.8V
I2C9, slave 0x3E, Reg0x01 = 0x12 → AVEE -5.8V
```

## 3. 电源归属判断 [已验证]

LCD 逻辑电源 1.8V 的来源有三种，必须沿原理图确认：

| 来源 | LK2 控制 | Kernel 控制 |
|---|---|---|
| AP GPIO | GPIO 高低 | gpio API / pinctrl |
| PMIC LDO（如 MT6366 VIBR） | PMIC Wrapper 寄存器（如 `MT6366_LDO_VIBR_CON0=0x1D08`, `VIBR_VOSEL_1V8=0x4`） | regulator framework（`mt6358_vibr_reg` + `regulator-boot-on`） |
| 固定电源 | 无需控制 | 无需控制 |

**坑**：旧项目用 GPIO 使能 1.8V，新板改接 PMIC LDO 后，继续操作 GPIO 无法控制该电源。同一 LDO 被改作 LCD 电源后要禁用原 consumer（如 vibrator 节点）。

## 4. LK2 与 Kernel 对照表 [已验证]

| 配置 | LK2 | Kernel |
|---|---|---|
| LCD 1.8V | MT6366 VIBR PMIC 寄存器 | `mt6358_vibr_reg` regulator |
| 偏压总线 | `BIAS_I2C_BUSNUM=9` | `&i2c9` |
| 偏压地址 | `0x3E` | `reg=<0x3e>` |
| AVDD/AVEE | Reg0/Reg1 写 `0x12` | Reg0/Reg1 写 `0x12` |
| AVDD/AVEE GPIO | GPIO103/GPIO150 | GPIO103/GPIO150 |
| LCD Reset | GPIO85 | GPIO85 |
| TP Reset | GPIO152 | GPIO152 |

**必须同步修改，不能只改一侧。** 否则 LK 能点屏、Kernel 接管异常。

## 5. Kernel DTS 示例 [已验证]

```dts
&regulator_vibrator { status = "disabled"; };   // 禁用原 vibrator consumer

&mt6358_vibr_reg {
    regulator-min-microvolt = <1800000>;
    regulator-max-microvolt = <1800000>;
    regulator-boot-on;
};

&i2c9 {
    clock-frequency = <400000>;
    status = "okay";
    aw37503@3e {
        compatible = "aw,aw37503";
        reg = <0x3e>;
        status = "okay";
    };
};

panel {
    vdd1v8-supply = <&mt6358_vibr_reg>;   // 原来是 vdd1v8-gpios
    avdd-gpios = <&pio 103 0>;
    avee-gpios = <&pio 150 0>;
    reset-gpios = <&pio 85 0>;
    tprst-gpios = <&pio 152 0>;
};
```

## 6. Kernel panel 驱动要点 [已验证]

- `devm_regulator_get(dev, "vdd1v8")` 获取 1.8V；`regulator_set_voltage(..., 1800000, 1800000)`。
- `prepare/unprepare` 中 `regulator_enable/disable`。
- AVDD/AVEE 分别向 `0x00/0x01` 写 `0x12`。
- **检查每个 I2C 写返回值**，失败打印明确日志（区分「GPIO 已拉高」与「寄存器确实写成功」）。

## 7. 排查路径 [已验证]

1. 先确认电源归属（GPIO / PMIC / 固定）。
2. 核对偏压三组参数：总线、地址、寄存器+编码（任一项不同都要分别修正）。
3. 同步检查 LK2 与 Kernel DTS。
4. 核对上电时序：1.8V → 偏压 → LCD Reset → DSI init。
5. 日志 + 仪器验证：

```text
正常: [LK/LCM] bias set to +/-5.8V: bus=9 addr=0x3e
异常: bias AVDD +5.8V write failed
实测: LCD 1.8V≈1.8V, LCM_AVDD_5V8≈+5.8V, LCM_AVEE_5V8≈-5.8V
```

逻辑分析仪确认 I2C9 波形：`START → 0x3E(W) → 0x00 → 0x12 → STOP`。

## 8. 试错记录 [已验证]

- 直接复制旧项目 I2C3：芯片/地址/寄存器相同 ≠ 板级总线相同（I2C 控制器由原理图连接决定）。
- 只改 Kernel 不改 LK2：显示电源链路横跨两个阶段。
- 屏幕亮就认为偏压正确：偏压 IC 默认值可能已足够点亮，必须查 I2C ACK + 返回值 + 实测电压。
- 把 `0x3E` 左移填 `0x7C`：Linux/MTK I2C 接口接收 7-bit 地址。
- 把 `mt_boot.c` WDT 改动与偏压总线混为同一根因（复盘按链路拆分）。

## 9. 快速定位命令 [已验证]

```bash
rg -n "BIAS_I2C_BUSNUM|BIAS_I2C_ADDR|BIAS_REG_AVDD|BIAS_REG_AVEE|BIAS_VOLTAGE" vendor/mediatek/proprietary/bootable/bootloader/lk2
rg -n "&i2c[0-9]+|aw37503@|reg = <0x3e>|vdd1v8-supply|avdd-gpios|avee-gpios" kernel-5.10/arch/arm64/boot/dts/mediatek
rg -n "regulator_get|regulator_enable|regulator_disable|aw37503_write_byte" kernel-5.10/drivers/gpu/drm/panel
```
