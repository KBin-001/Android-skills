# Camera Sensor 合入速查模板

> 用途：合入新 sensor 时逐项填写，对照 references/ 中各项规则检查。
> 状态：GC08A8/HI1333/BF2257 列为本项目已验证实测值；新 sensor 列为空白待填。

## 1. 硬件对应表

| 项 | GC08A8 (MAIN/cam0) [已验证] | HI1333 (SUB/cam1) [已验证] | BF2257 (MAIN2/cam2) [已验证] | 新 Sensor |
|---|---|---|---|---|
| Sensor ID | 0x08a8 | 0x1333 | 0x2257 | |
| I2C Bus | DEV_0 | DEV_1 | DEV_2 | |
| I2C Addr | （FAE datasheet） | （FAE datasheet） | （FAE datasheet） | |
| RST GPIO | GPIO20 | GPIO16 | GPIO22 | |
| PDN GPIO | GPIO19 | GPIO15 | 无 PDN | |
| MCLK (Kernel) | GPIO128/CMMCLK2 | GPIO126/CMMCLK0 | GPIO129/CMMCLK3 | |
| MCLK (HAL) | CUSTOM_CFG_MCLK_3 | CUSTOM_CFG_MCLK_1 | CUSTOM_CFG_MCLK_4 | |
| CSI Port | PORT_1 | PORT_0 | PORT_2 | |
| 方向 dir | REAR | FRONT | FRONT (MAIN2) | |

## 2. 电源表

| Rail | GC08A8 [已验证] | HI1333 [已验证] | BF2257 [已验证] | 新 Sensor |
|---|---|---|---|---|
| AVDD | 2.8V GPIO71 | 2.8V GPIO71(共用) | 2.8V GPIO74 | |
| DOVDD | 1.8V GPIO72 | 1.8V GPIO72(共用) | 1.8V GPIO73 | |
| DVDD | 1.2V GPIO75 | 1.2V GPIO76 | 1.2V GPIO37 | |
| DVDD1 | VMC 2.8V | VMC 2.8V | VMC 2.8V | |
| AFVDD | 2.8V（DW9714AF 马达） | — | — | |

## 3. Power Sequence 模板

GC08A8 [已验证]：

```c
{SensorMCLK, Vol_High, 0}, {PDN, Vol_Low, 0}, {RST, Vol_Low, 0},
{DOVDD, Vol_1800, 1}, {AVDD, Vol_2800, 1}, {DVDD, Vol_1200, 5},
{AFVDD, Vol_2800, 1}, {PDN, Vol_High, 1}, {RST, Vol_High, 2}
```

BF2257（无 PDN）[已验证]：

```c
{SensorMCLK, Vol_High, 0}, {RST, Vol_Low, 0},
{DVDD1, Vol_2800, 1}, {DOVDD, Vol_1800, 1}, {AVDD, Vol_2800, 1},
{DVDD, Vol_1200, 5}, {RST, Vol_High, 2}
```

新 Sensor Power Sequence（依据 datasheet + 原理图填写）：

```c
{
    SENSOR_DRVNAME_<SENSOR>_MIPI_RAW,
    {
        {SensorMCLK, Vol_High, 0},
        {<PIN>, <VOLTAGE>, <DELAY>},
        ...
    },
},
```

## 4. imgsensor_cfg_table.c Backend 模板（本项目已验证值）

```c
{IMGSENSOR_HW_PIN_MCLK,  IMGSENSOR_HW_ID_MCLK},
{IMGSENSOR_HW_PIN_AVDD,  IMGSENSOR_HW_ID_GPIO},      // 或 REGULATOR
{IMGSENSOR_HW_PIN_DOVDD, IMGSENSOR_HW_ID_GPIO},
{IMGSENSOR_HW_PIN_DVDD,  IMGSENSOR_HW_ID_GPIO},
{IMGSENSOR_HW_PIN_DVDD1, IMGSENSOR_HW_ID_REGULATOR},
{IMGSENSOR_HW_PIN_PDN,   IMGSENSOR_HW_ID_GPIO},
{IMGSENSOR_HW_PIN_RST,   IMGSENSOR_HW_ID_GPIO},
```

> 此表必须与 DTS 的 `camX_pin_vcam* = "gpio"/"regulator"` 完全一致。

## 5. 合入后验证清单（开机检查）

- [ ] `adb shell dmesg | grep -i <sensor>` 出现 sensor id / power on
- [ ] `adb shell cat /proc/modules | grep imgsensor` KO 已加载
- [ ] `adb shell cat /sys/kernel/debug/regulator/regulator_summary | grep -i vmc`（若用 VMC）
- [ ] `adb shell cat /proc/mtk_gpio/soc.pinctrl | grep -E "^071:|^072:|^075:"` 电源 GPIO 电平
- [ ] I2C ACK、读到正确 Sensor ID
- [ ] HAL 枚举 MAIN/SUB/MAIN2 正确
- [ ] Preview / capture / 切换 / flash / suspend-resume 通过
