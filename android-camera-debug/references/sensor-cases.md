# Sensor 型号特例（案例库，不污染主流程）

> 分层：Sensor 型号特例。这里的经验绑定到具体 sensor，通用场景请走 SKILL.md 主流程与其他 references。状态：`[已验证]` = 项目闭环；`[待验证]` = 推测。

## GC08A8（后置主摄 MAIN / cam0）[已验证]

- Sensor ID：`0x08a8`（注意 Vendor header 曾写 `0x08a3`，以驱动实测/FAE datasheet 为准）。
- I2C：DEV_0；RST=GPIO20、PDN=GPIO19；MCLK=GPIO128/CMMCLK2（HAL `CUSTOM_CFG_MCLK_3`）。
- 电源：AVDD=2.8V(GPIO71)、DOVDD=1.8V(GPIO72)、DVDD=1.2V(GPIO75)、DVDD1=VMC 2.8V。
- Power sequence（本项目）：

```c
{SensorMCLK, Vol_High, 0}, {PDN, Vol_Low, 0}, {RST, Vol_Low, 0},
{DOVDD, Vol_1800, 1}, {AVDD, Vol_2800, 1}, {DVDD, Vol_1200, 5},
{AFVDD, Vol_2800, 1}, {PDN, Vol_High, 1}, {RST, Vol_High, 2}
```

- 马达：DW9714AF（`lenslist.cpp` 注册 `{GC08A8_SENSOR_ID, DUMMY_MODULE_ID, DW9714AF_LENS_ID, "DW9714AF", NULL}`）。
- 已点亮并完成合入验证。合入要点：Kernel/Vendor ID 一致、五层链路齐全、`cam0_enable_sensor = "gc08a8_mipi_raw"`。

## HI1333（前置主摄 SUB / cam1）[已验证]

- Sensor ID：`0x1333`。
- I2C：DEV_1；RST=GPIO16、PDN=GPIO15；MCLK=GPIO126/CMMCLK0（HAL `CUSTOM_CFG_MCLK_1`）。
- 电源：AVDD=2.8V(GPIO71)、DOVDD=1.8V(GPIO72)、DVDD=1.2V(GPIO76)、DVDD1=VMC。
- ⚠️ **cam0 与 cam1 共用 GPIO71（AVDD）、GPIO72（DOVDD）**——修改上下电要考虑共享电源。
- 上电顺序与 GC08A8 相同。

## BF2257（前置副摄 MAIN2 / cam2）[已验证]

- Sensor ID：`0x2257`。名称统一 `bf2257_mipi_raw`（patch 文件名写成 `bf2577` 是坑）。
- I2C：DEV_2；RST=GPIO22、**无 PDN**；MCLK=GPIO129/CMMCLK3（HAL `CUSTOM_CFG_MCLK_4`）。
- 电源：AVDD=2.8V(GPIO74)、DOVDD=1.8V(GPIO73)、DVDD=1.2V(GPIO37)、DVDD1=VMC。
- **上电序列不要加 PDN**：

```c
{SensorMCLK, Vol_High, 0}, {RST, Vol_Low, 0},
{DVDD1, Vol_2800, 1}, {DOVDD, Vol_1800, 1}, {AVDD, Vol_2800, 1},
{DVDD, Vol_1200, 5}, {RST, Vol_High, 2}
```

- 位置：硬件接 cam2，逻辑用 MAIN2 + `dir = FRONT`（`.sensorIdx = IMGSENSOR_SENSOR_IDX_MAIN2, .mclk = CUSTOM_CFG_MCLK_4, .port = CUSTOM_CFG_CSI_PORT_2, .dir = CUSTOM_CFG_DIR_FRONT, .orientation = 90`）。
- 前置副摄必须写 FRONT，否则 Framework 当后摄。

## S5K3M5SX（MT8391/MT8189 平台）[已验证]

- 案例：HEIF 13M 3:2 成片降为 0.8M（`720×1080`）。
- 根因：metadata 声明奇数 `4415×2943`（BLOB + YUV 两处），App 拒绝奇数 HEIC 尺寸并回退。
- 修复：两处同步改为 `4416×2944`（16 对齐）。详见 references/metadata-tuning.md。
- 经验沉淀：尺寸不一致按「设置值 → Surface → HAL stream → Encoder → 文件」逐层比对，修 metadata 不删 App 保护。

## 通用 sensor 特例观察 [待验证]

- 不同 sensor 的 MCLK/CMMCLK 与 HAL `CUSTOM_CFG_MCLK_N` 的对应关系可能不同（本项目 CMMCLK2→MCLK_3、CMMCLK0→MCLK_1、CMMCLK3→MCLK_4），**必须按原理图 GPIO 复用核对**，不要凭数字规律推断。
- 无 PDN sensor（如 BF2257）在 FAE 驱动里可能是常见情况，上电序列勿硬加。
