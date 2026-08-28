# 项目特例（不要当作通用模板）

> 分层：项目特例。这些内容在 MT6789/MT8781 项目中已验证，但**不要**照搬进其他项目。

## 1. `pdn` → `pnd` 改名 [已验证]

本项目 `imgsensor_hw.c` 把 Camera Pin 名称 `"pdn"` 改为 `"pnd"`，DTS 同步使用 `camX_pin_pnd`、`camX_pnd0/1`。这是项目定制行为，新项目必须查原工程实际用 `"pdn"` 还是 `"pnd"`，不要为合 sensor 全局替换（会影响其他 Camera slot）。

## 2. VMC 共享供电 [已验证]

- Camera 的 DVDD1 走 `mt6358_vmc_reg`（VMC 通常作为 SD 卡 I/O 电源，本项目 Camera 复用了它）。
- 板级 DTS 加了 `regulator-boot-on + regulator-always-on` 才点亮（详见 references/power-sequence.md 第 6 节）。
- 风险：VMC 同时被 MSDC `vqmmc-supply` 使用，always-on 可能影响 SD 卡电压切换。量产方案应通过 consumer 正常申请/释放。

## 3. 电源方案：Regulator → GPIO [已验证]

本项目 Camera 电源从“Camera Framework → Regulator → RT5133 LDO”改为“Framework → GPIO backend → Camera Power Enable GPIO”，DTS 中 `camX_pin_vcama/vcamio/vcamd = "gpio"` 且注释掉 supply。**必须与 imgsensor_cfg_table.c 的 backend 选择保持一致。**

## 4. Flash 链路（ocp81378）[已验证]

- Flash IC：`ocp81378.ko`（加入 `ko_order_table.csv` 打包）。
- HAL 映射：`flash_custom_v4l2.cpp` 中 `{STROBE_TYPE_REAR, 1, 1, "ocp81378-led0", 0, 0}`。
- 现象：Camera 出图正常但闪光灯按钮没反应 → 单独检查 Flash 驱动链路（KO → V4L2 device → flash_custom_v4l2 → HAL）。

## 5. Patch 文件名坑 [已验证]

本项目 patch 文件名写成了 `bf2577`，实际 sensor 名称必须统一为 `bf2257_mipi_raw`。合入时**以代码中的 sensor 名为准**，文件名写错不影响功能但容易误导。

## 6. GC08A8 Sensor ID 不一致 [已验证]

Kernel `kd_imgsensor.h` = `0x08a8`，Vendor `kd_imgsensor.h` = `0x08a3`，两边不一致。本项目以此作为排查模板：Camera 无法识别时优先核对 ID 一致性（详见 references/sensor-list-registration.md）。
