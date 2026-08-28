# Power Sequence / 电压 / GPIO / MCLK / RST

> 分层：MTK 平台规则（`[已验证]` 为项目实测，`[待验证]` 为通用推测）

## 1. Power Sequence 位置与格式 [已验证]

文件：`kernel_device_modules-6.12/drivers/misc/mediatek/imgsensor/src/common/v1_1/imgsensor_pwr_seq.c`

```c
#if defined(GC08A8_MIPI_RAW)
{
    SENSOR_DRVNAME_GC08A8_MIPI_RAW,
    {
        {SensorMCLK, Vol_High, 0},
        {PDN,        Vol_Low,  0},
        {RST,        Vol_Low,  0},
        {DOVDD,      Vol_1800, 1},
        {AVDD,       Vol_2800, 1},
        {DVDD,       Vol_1200, 5},
        {AFVDD,      Vol_2800, 1},   // 有 AF/马达才需要
        {PDN,        Vol_High, 1},
        {RST,        Vol_High, 2}
    },
},
#endif
```

字段含义：`{PIN, 电平/电压, delay_ms}`。delay 是该步骤之后的等待时间。

## 2. 各 rail 电压（本项目 GC08A8）[已验证]

| Rail | 电压 |
|---|---:|
| DOVDD | 1.8 V |
| AVDD | 2.8 V |
| DVDD | 1.2 V |
| DVDD1 | 2.8 V（VMC regulator） |
| AFVDD | 2.8 V（有马达时） |

**不要照抄**：必须按原理图 + Sensor datasheet + FAE power sequence 核对：AVDD/DVDD/DOVDD 各多少 V、AFVDD 是否存在、MCLK 先开后开、PDN/RST 高有效还是低有效、各 delay 多少 ms。

## 3. 无 PDN 的 Sensor（BF2257）[已验证]

BF2257 硬件没有 PDN，**不要硬加 PDN**：

```c
{SensorMCLK, Vol_High, 0},
{RST,        Vol_Low,  0},
{DVDD1,      Vol_2800, 1},
{DOVDD,      Vol_1800, 1},
{AVDD,       Vol_2800, 1},
{DVDD,       Vol_1200, 5},
{RST,        Vol_High, 2}
```

## 4. 电源 backend 一致性 [已验证]

`imgsensor_cfg_table.c` 决定 power sequence 中每个 PIN 走 GPIO 还是 REGULATOR：

```c
{IMGSENSOR_HW_PIN_MCLK,  IMGSENSOR_HW_ID_MCLK},      // MCLK 控制器
{IMGSENSOR_HW_PIN_AVDD,  IMGSENSOR_HW_ID_GPIO},      // 本项目 AVDD 走 GPIO
{IMGSENSOR_HW_PIN_DOVDD, IMGSENSOR_HW_ID_GPIO},
{IMGSENSOR_HW_PIN_DVDD,  IMGSENSOR_HW_ID_GPIO},
{IMGSENSOR_HW_PIN_DVDD1, IMGSENSOR_HW_ID_REGULATOR}, // DVDD1 走 VMC regulator
{IMGSENSOR_HW_PIN_PDN,   IMGSENSOR_HW_ID_GPIO},
{IMGSENSOR_HW_PIN_RST,   IMGSENSOR_HW_ID_GPIO},
```

**DTS 写 GPIO 而 cfg_table 写 REGULATOR（或反之）= 对不上，上电必然异常。**

## 5. DTS 电源与 pinctrl [已验证]

文件：`cust_mt6789_camera.dtsi`

- GPIO 电源：`camX_pin_vcama/vcamio/vcamd = "gpio"`，配套 `camX_ldo_vcama_0/1` 等 pinctrl。
- Regulator 电源：`camX_vcama-supply = <&rt5133_ldo4>` + `camX_pin_vcama = "regulator"`。
- Sensor 绑定：`camX_enable_sensor = "xxx_mipi_raw";`
- **pinctrl-names 与 pinctrl-N 索引必须一一对应**：新增中间节点却不同步后面 index → 名字与 GPIO state 全部错位，上电诡异。

## 6. VMC 供电（DVDD1）[已验证 — 本项目特例]

现象：电源使能 GPIO 已拉高但实测没有电压。原因：Camera 的 DVDD1 链路依赖 VMC，VMC 未开启时 GPIO 高但后面没有输入电源。

修复（放在板级 DTS，不要改公共 dtsi）：

```dts
&mt6358_vmc_reg {
    regulator-boot-on;    // 接管 bootloader 已打开的电源
    regulator-always-on;  // 运行期不允许 regulator 关闭
};
```

完整链路必须四处对应：

```text
imgsensor_pwr_seq.c 的 DVDD1 2.8V
  → imgsensor_cfg_table.c 选择 REGULATOR
  → cust_mt6789_camera.dtsi 的 camX_vcamd1-supply
  → mt6358_vmc_reg → PMIC VMC 输出
```

**注意 SD 卡冲突**：VMC 同时被 MSDC 用作 `vqmmc-supply`。强制 always-on 可能影响 SD 卡 1.8/2.8V 切换或低功耗关断。量产方案最好让 Camera 通过 `DVDD1` consumer 正常申请/释放，不要长期依赖 always-on 绕过管理。

确认命令：

```bash
adb shell cat /sys/kernel/debug/regulator/regulator_summary | grep -i vmc
adb shell cat /proc/mtk_gpio/soc.pinctrl | grep -E "^071:|^072:|^075:"
```

判断：VMC 没 enable → 查 DTS 是否进 DTB/DTBO、supply 名称是否匹配；VMC enable 但 GPIO 没拉高 → 查上电序列与 pinctrl；都正常仍无电压 → 查 LDO/Load Switch 板级；电压正常仍读不到 ID → 继续查 MCLK/RST/PDN/I2C。

## 7. PDN/PND 命名 [已验证 — 项目特例]

本项目 `imgsensor_hw.c` 把 `"pdn"` 改成了 `"pnd"`（DTS 同步用 `camX_pin_pnd`、`camX_pnd0/1`）。这是**项目定制**，不要作为通用模板复制。新项目先查原工程用 `"pdn"` 还是 `"pnd"`，不要为合 sensor 全局改，否则影响其他 slot：

```bash
grep -R '"pdn"\|"pnd"' kernel_device_modules-6.12/drivers/misc/mediatek/imgsensor kernel_device_modules-6.12/arch/arm64/boot/dts/mediatek
```
