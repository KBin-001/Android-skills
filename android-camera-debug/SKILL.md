---
name: android-camera-debug
description: >-
  Android/MTK Camera 排障与 bring-up 技能。当用户报告任何相机问题——Camera 打不开、预览黑屏/花屏、拍照/录像异常、摄像头切换卡顿、传感器 probe 失败、Sensor ID 读不到、I2C 通信失败、上电时序问题、前后摄切换异常、HEIF/JPEG 分辨率降级、颜色偏色、无法对焦——或要求合入新 Camera sensor 驱动（GC08A8/HI1333/BF2257 等）、检查 sensorlist/SensorListV2、排查 kernel imgsensor 日志与 Camera HAL 日志、修改 BUILD.bazel/defconfig/CameraConfig.mk/mtkcamvars.go、分析 power sequence/AVDD/DOVDD/DVDD/MCLK/RST、检查 metadata/tuning/wininfo/streaming_control/sensor_output_dataformat 时，必须使用本技能。按「现象→log→调用链→配置→硬件时序→修改→编译→验证」流程系统排查，避免凭经验乱改。
license: Apache-2.0 (LICENSE.txt)
compatibility: Android/MTK 平台 (MT6789/MT8781/MT8391 等), Kernel 6.x, Legacy imgsensor framework; 需要 adb 与代码树访问
metadata:
  author: Kevin
  source: D:\Kevin\笔记总结
  verified-cases: GC08A8, HI1333, BF2257, S5K3M5SX, mt6358_vmc
---

# Android Camera Debug (MTK)

把作者的 Camera 调试经验从“案例知识”转成“可重复执行的排障流程”。核心原则：**先分层定位，再动手改**。

## 主流程（必须按顺序执行）

**现象 → log → 调用链 → 配置 → 硬件时序 → 修改 → 编译 → 验证**

1. **现象** — 记录可复现的现象、复现步骤、影响范围（只影响某 sensor？某格式？某分辨率？）
2. **Log** — 收集 kernel dmesg + Camera HAL logcat，找**第一有效异常**（不是最后的结果日志）
3. **调用链** — 确定问题在哪一层：硬件 → Kernel imgsensor → Vendor SensorList → Metadata/Tuning → CameraProvider → App
4. **配置** — 检查 sensor 名称/ID/位置/电源 backend 的一致性（见下）
5. **硬件时序** — 核对 power sequence、MCLK、RST/PDN、电压 rail
6. **修改** — 按根因改对应层，先改配置/时序类低成本项
7. **编译** — Kernel (MGK) 与 Vendor 镜像分开编译，注意 Bazel 名单
8. **验证** — 开机看 ID → preview → capture → 切换 → flash → suspend/resume

## 快速分诊（现象 → 优先检查层）

| 现象 | 第一怀疑层 | 参考 |
|---|---|---|
| Sensor ID 读不到 / I2C fail | Power/GPIO/MCLK/I2C/驱动 | references/mtk-camera-architecture.md |
| 编译成功但 Camera 打不开 | SensorList / Metadata / Tuning | references/sensor-list-registration.md |
| 出图但偏色/过曝 | tuning / sensor_output_dataformat | references/metadata-tuning.md |
| 只有低分辨率没有高分辨率 | metadata 尺寸声明 / 对齐 | references/metadata-tuning.md |
| 切换卡顿 | HAL stream 配置 / 预取 | references/camera-switch-lag.md |
| 能 probe 但 App 枚举不到 | HAL SensorList 两处注册 | references/sensor-list-registration.md |
| 电源有 GPIO 无电压 | VMC/regulator 链路 | references/power-sequence.md |

## 8 个一致性检查（合入/排障必查）

1. **Sensor 名称**：`xxx_mipi_raw` 在 Kernel = Vendor = Build Config = DTS
2. **Sensor ID**：驱动实际读到的 ID = Kernel kd_imgsensor.h = Vendor kd_imgsensor.h（⚠️ GC08A8 曾出现 0x08a8 vs 0x08a3 不一致）
3. **电源 rail**：Power Sequence = imgsensor_cfg_table = DTS = 原理图
4. **GPIO**：RST/PDN/AVDD/DVDD/DOVDD 在 DTS 与原理图一致
5. **位置**：MAIN/SUB/MAIN2 与 CAM0/CAM1/CAM2 对应（前置副摄可用 MAIN2 + dir=FRONT）
6. **SensorList**：Kernel `imgsensor_sensor_list.c` + Vendor `sensorlist.cpp`（common 和 tablet 两处）
7. **Metadata**：sensor metadata + platform metadata + tuning 齐全
8. **Build**：CameraConfig.mk + ProjectConfig.mk + defconfig + BUILD.bazel + mtkcamvars.go

> 执行 `scripts/check_sensor_consistency.sh <sensor_name>` 可自动完成第 1/2/6/8 项检查。

## 日志关键词速查

- Kernel imgsensor：`imgsensor` `sensor_id` `i2c` `ERROR_SENSOR_CONNECT_FAIL` `mclk` `regulator` `cam_pwr`
- Camera HAL：`mtkcam` `camera` `configureStreams` `metadata` `tuning` `IdxMgr` `ISP_mapping` `ISP_param`
- 尺寸/格式：`updatePictureSize` `requestSize` `targetSize` `odd HEIC size` `HEIC`（见 references/metadata-tuning.md）

> 详细日志采集与分析见 `scripts/collect_camera_logs.ps1` 与 references/log-analysis.md。

## 知识分层

- **通用排障规则**：本 SKILL.md 主流程 + references/log-analysis.md、references/camera-switch-lag.md
- **MTK 平台规则**：references/mtk-camera-architecture.md、references/sensor-list-registration.md、references/power-sequence.md、references/metadata-tuning.md、references/build-compile.md
- **项目特例**：references/project-specific.md（pdn→pnd 改名、VMC 共享、patch 管理）
- **Sensor 型号特例**：references/sensor-cases.md（GC08A8/HI1333/BF2257 具体经验，不污染主流程）

## 验证状态标记

- `[已验证]` — 来自已闭环复盘笔记，可直接复用
- `[待验证]` — 推测性/通用结论，使用前必须在目标平台复核

## 许可证

本 Skill 以 [Apache-2.0](LICENSE.txt) 开源。知识整理自作者个人的 Android/MTK Camera 调试笔记；案例与排障结论标记遵循上述「已验证/待验证」约定，使用前请自行复核。

## 使用本技能的注意事项

- **不要跳过分层定位直接改代码**。现象相同根因可能不同。
- **不要照搬其他项目的 power sequence / DTS**，必须按原理图 + datasheet 核对。
- Sensor 能 probe ≠ Camera 完整合入；Kernel 编进 KO ≠ 实际加载生效。
- 涉及 Vendor/Device 侧修改（metadata/tuning/sensorlist/mtkcamvars）时，只编 MGK 无效，必须编对应 Vendor/Vext 镜像。
- 找不到根因时回到「第一有效异常」：它通常出现在问题链的第一次 fallback/拒绝处。
