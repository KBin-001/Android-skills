# Sensor 注册与 SensorList（Kernel / HAL）

> 分层：MTK 平台规则 + 少量通用规则；`[已验证]` 来自本项目复盘，`[待验证]` 为推测

## 1. Kernel 侧注册链 [已验证]

驱动目录放进 imgsensor 后，MTK Framework 还不知道它存在，必须完成三处绑定：

```c
// kd_imgsensor.h —— ID 与名称
#define GC08A8_SENSOR_ID               0x08a8
#define SENSOR_DRVNAME_GC08A8_MIPI_RAW "gc08a8_mipi_raw"

// imgsensor_sensor_list.h —— Init 函数声明
UINT32 GC08A8_MIPI_RAW_SensorInit(struct SENSOR_FUNCTION_STRUCT **pfFunc);

// imgsensor_sensor_list.c —— 注册三元组
#if defined(GC08A8_MIPI_RAW)
{
    GC08A8_SENSOR_ID,
    SENSOR_DRVNAME_GC08A8_MIPI_RAW,
    GC08A8_MIPI_RAW_SensorInit
},
#endif
```

即 `Sensor ID ─ Driver Name ─ Init Function` 三者绑定。换 sensor 全局搜 `SENSOR_DRVNAME_XXX`。

## 2. Sensor ID 一致性（重点坑）[已验证]

**⚠️ GC08A8 项目曾出现：Kernel `kd_imgsensor.h` 写 `0x08a8`，Vendor `kd_imgsensor.h` 写 `0x08a3`。**

正确做法：以 Sensor 驱动实际读取的 Chip ID / FAE datasheet 为准，确保四处一致：

```text
Kernel ID = Vendor ID = Sensor 驱动返回 ID = HAL SensorList ID
```

排查命令：

```bash
grep -R "sensor_id" kernel_device_modules-6.12/drivers/misc/mediatek/imgsensor/src/common/v1_1/<sensor>/
grep -Rni "<id>" kernel_device_modules-6.12/drivers/misc/mediatek/imgsensor mediatek/vendor/camera mediatek/proprietary/custom
```

## 3. Vendor HAL 侧注册（两处）[已验证]

Kernel 能 probe ≠ HAL 认识。两个 sensorlist.cpp 都要注册：

```text
vendor/mediatek/proprietary/custom/common/hal/imgsensor_src/sensorlist.cpp
vendor/mediatek/proprietary/custom/<plat>/hal/imgsensor_src/tablet/sensorlist.cpp
```

```cpp
#if defined(GC08A8_MIPI_RAW)
RAW_INFO_M(
    GC08A8_SENSOR_ID,
    DEFAULT_MODULE_INDEX,
    DEFAULT_MODULE_ID,
    SENSOR_DRVNAME_GC08A8_MIPI_RAW,
    CAM_CALGetCalData
),
#endif
```

`CAM_CALGetCalData` 接入 Camera Calibration（EEPROM/OTP/AWB/LSC/Module ID）。后续遇到校准类问题，不要只盯 sensor 驱动。

## 4. I2C 与 Sensor ID 读取 [已验证]

驱动内重点确认：`sensor_id`、`i2c_addr_table`、`get_imgsensor_id()` 能正常读到 ID。

Sensor ID 读不到的排查顺序（从底向上，不要一上来怀疑 HAL）：

```text
① AVDD → ② DOVDD → ③ DVDD → ④ RESET 电平 → ⑤ PDN 电平 → ⑥ MCLK 波形
→ ⑦ I2C Address → ⑧ I2C SDA/SCL 波形 → ⑨ Sensor ID register → ⑩ ID 宏一致性
```

常见日志：`I2C read sensor ID fail` / `sensor connect fail` / `ERROR_SENSOR_CONNECT_FAIL`。

## 5. streaming_control [待验证]

`streaming_control`（sensor 驱动内 `set_streaming_control` / preview 开启/关闭函数）控制 sensor 的 streaming 状态，通常在 preview/record 开始与结束时被调用。本知识库暂无该函数的直接故障案例，仅作为通用检查点：

- 若 preview 黑屏但 ID 正常：检查 streaming 是否被正确开启（`streaming_control(1)`）、帧率设置（`sensor_output_dataformat`/`pclk`/`line_length`/`frame_length`）。
- 若关闭 camera 后再次打开失败：检查 streaming off 时序与 power down 是否完整。

> [待验证] 以上为通用 MTK imgsensor 行为，具体平台请以 `v1_1/<sensor>/xxxmipi_Sensor.c` 源码为准。

## 6. SensorListV2 [待验证]

本项目使用 Legacy imgsensor framework（`imgsensor_sensor_list.c` 路径）。若目标代码树存在 SensorListV2 框架（MTK 新平台的 sensor 列表 v2 机制，通常位于 `imgsensor_sensor_list_v2.*` 或 HAL 侧独立 sensor list 目录），注册入口与文件位置不同。

- [待验证] 在遇到 SensorListV2 报错或 sensor 不在列表中时，先全局搜索 `SensorListV2` / `imgsensor_sensor_list_v2` 确认框架存在，再按其目录结构注册；不要硬套本项目 legacy 路径。
- 若平台同时保留 legacy 与 v2，可能两套列表都需要注册（与本项目保留 legacy metadata 兼容路径同理）。
