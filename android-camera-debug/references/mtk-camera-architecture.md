# MTK Camera 整体链路与目录映射

> 分层：MTK 平台规则（平台：MT6789/MT8781，Kernel 6.x，Legacy imgsensor framework）

## 1. 五层链路 [已验证]

Camera 合入不是“把 sensor.c 丢进 kernel”。完整链路：

```
Sensor 原厂/FAE 驱动
  → Kernel Sensor Driver（驱动文件 + ID + SensorList + Power Sequence + HW 映射 + DTS）
  → Kernel probe OK
  → Vendor Camera HAL（sensorlist.cpp + CameraConfig.mk + sensor HAL source）
  → Metadata/Tuning/ISP（imgsensor_metadata + *_tuning + *_IdxMgr + ISP_mapping + ISP_param）
  → Android Camera HAL → App 出图
```

排查/合入至少按 5 个层级检查：① Sensor Driver ② Kernel Registration ③ DTS/Power ④ Vendor HAL ⑤ Metadata/Tuning/Build。

## 2. 关键路径映射（MT6789/MT8781, Kernel 6.12）

| 层级 | 文件 | 作用 |
|---|---|---|
| Kernel Driver | `kernel_device_modules-6.12/drivers/misc/mediatek/imgsensor/src/common/v1_1/<sensor>/` | Sensor 真正驱动（`xxxmipi_Sensor.c/.h` + Makefile） |
| Kernel ID | `.../imgsensor/inc/kd_imgsensor.h` | `#define XXX_SENSOR_ID` 与 `SENSOR_DRVNAME_XXX_MIPI_RAW` |
| Kernel 注册 | `.../imgsensor/src/common/v1_1/imgsensor_sensor_list.h/.c` | `SensorInit` 声明 + `{ID, DRVNAME, SensorInit}` 三元组注册 |
| Power 时序 | `.../imgsensor/src/common/v1_1/imgsensor_pwr_seq.c` | sensor 上电/下电序列 |
| HW Backend | `.../imgsensor/src/common/v1_1/camera_hw/imgsensor_cfg_table.c` | 每个 PIN 用 GPIO 还是 REGULATOR |
| Pin Name | `.../imgsensor/src/common/v1_1/imgsensor_hw.c` | Camera Pin 名称（本项目定制为 pnd） |
| DTS | `kernel_device_modules-6.12/arch/arm64/boot/dts/mediatek/cust_mt6789_camera.dtsi` | RST/PDN/MCLK/电压 GPIO + `camX_enable_sensor` + supply |
| Defconfig | `kernel_device_modules-6.12/arch/arm64/configs/mgk_64_k612_defconfig` | `CONFIG_CUSTOM_KERNEL_IMGSENSOR="..."` |
| Bazel | `kernel_device_modules-6.12/drivers/misc/mediatek/imgsensor/src/BUILD.bazel` | `config_cust_kernel_imgsensor = "..."`，决定进 KO |
| Device mk | `device/mediatek/mt6789/CameraConfig.mk` `device-camera.mk` | HAL/Kernel sensor 名单 + MAIN/SUB/MAIN2 |
| Project | `device/mediateksample/<proj>/ProjectConfig.mk` | 项目最终启用名单 |
| HAL ID | `device/mediatek/vendor/camera/kernel-headers/kd_imgsensor.h` | Device 侧 ID/名称副本（与 Kernel 必须一致） |
| HAL List | `vendor/mediatek/proprietary/custom/common/hal/imgsensor_src/sensorlist.cpp` + `custom/<plat>/hal/imgsensor_src/tablet/sensorlist.cpp` | RAW_INFO_M 注册（两处都要） |
| Soong | `vendor/mediatek/proprietary/scripts/soong/mtkcam/mtkcamvars.go` | tuning/IdxMgr/ISP/libCamera 模块注册 |
| Metadata | `custom/common/hal/imgsensor_metadata/sensor/<sensor>/` + `custom/common/legacy/hal/imgsensor_metadata/sensor/<sensor>/` | Sensor 静态能力（两套 provider 都要补） |
| 平台 Metadata | `custom/<plat>/hal/imgsensor_metadata/<sensor>/` | 平台/项目级 metadata |
| Tuning | `custom/<plat>/hal/imgsensor/ver1/<sensor>/` | ISP 场景参数 |
| MCLK 枚举 | `vendor/.../custom/<plat>/hal/inc/camera_custom_imgsensor_cfg.h` | CUSTOM_CFG_MCLK_1 起 |

## 3. MCLK 对应规则 [已验证]

- Kernel `mclk.c` 按 sensor index 拼 `"cam%d_mclk_%s"`：MAIN→`cam0_mclk_*`，SUB→`cam1_mclk_*`，MAIN2→`cam2_mclk_*`。
- 实际输出哪路 CLK 由 DTS pinmux 决定：cam0→GPIO128/CMMCLK2，cam1→GPIO126/CMMCLK0，cam2→GPIO129/CMMCLK3。
- Vendor HAL 枚举从 `CUSTOM_CFG_MCLK_1 = 0` 开始：CMMCLK0→MCLK_1，CMMCLK2→MCLK_3，CMMCLK3→MCLK_4。
- 数字差 1 是正常的，不要凭数字乱改；先按原理图确认 GPIO 复用功能，再同时核对 DTS 与 `cfg_setting_imgsensor.cpp`。

## 4. 位置与方向 [已验证]

- `CUSTOM_*_MAIN_IMGSENSOR / SUB / MAIN2` 决定逻辑位置；`CAM0/CAM1/CAM2` 是硬件 slot。
- **前置副摄可用 MAIN2 + `dir = FRONT`**（本项目 BF2257 接 cam2 用 MAIN2 + CUSTOM_CFG_DIR_FRONT）。MAIN2 不等于后摄。
- `cfg_setting_imgsensor.cpp` 里 `.sensorIdx/.mclk/.port/.dir/.orientation/.fov` 必须与 Device mk、DTS、MCLK 枚举全部一致。

## 5. 最容易漏的 8 处 [已验证]

1. 名称大小写/拼写不一致（`bf2257` 别写成 `bf2577`/`BF2257_mipi_raw`）。
2. 只加驱动源码，没加 defconfig 和 `BUILD.bazel`（两个名单都要）。
3. Kernel `kd_imgsensor.h` 改了，Device 副本没改。
4. Kernel 读到 ID，但 Vendor 两个 sensorlist.cpp 没注册。
5. 只复制 tuning，没补四套 metadata 路径（common + legacy + 平台 ver1 + 平台 metadata）。
6. DTS MCLK pinmux 与 HAL MCLK 枚举不对应。
7. `imgsensor_cfg_table.c` 写 GPIO 但 DTS 按 regulator 配（或反过来）。
8. Sensor 没有 PDN 却在上电序列里控制 PDN（BF2257 无 PDN）。
