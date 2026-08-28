# 编译与构建（BUILD.bazel / defconfig / mk / Soong）

> 分层：MTK 平台规则（`[已验证]` 来自项目）

## 1. Kernel 侧：两个名单都要改 [已验证]

只改 defconfig 或只改 BUILD.bazel，sensor 可能不进 `imgsensor_isp6s.ko`。

```text
# 1) defconfig
kernel_device_modules-6.12/arch/arm64/configs/mgk_64_k612_defconfig
CONFIG_CUSTOM_KERNEL_IMGSENSOR="gc08a8_mipi_raw hi1333_mipi_raw bf2257_mipi_raw"

# 2) Bazel KO 名单
kernel_device_modules-6.12/drivers/misc/mediatek/imgsensor/src/BUILD.bazel
config_cust_kernel_imgsensor = "gc08a8_mipi_raw hi1333_mipi_raw bf2257_mipi_raw"
```

验证 KO 是否包含 sensor 字符串（只证明进 KO，不证明实际加载生效）：

```bash
strings imgsensor_isp6s.ko | grep -Ei "gc08a8|hi1333|bf2257"
adb shell cat /proc/modules | grep imgsensor
```

## 2. Device/Vendor 侧 [已验证]

```text
device/mediatek/mt6789/CameraConfig.mk      # CUSTOM_HAL/KERNEL_IMGSENSOR + MAIN/SUB/MAIN2
device/mediatek/mt6789/device-camera.mk     # 收集 tuning 模块
device/mediateksample/<proj>/ProjectConfig.mk  # 项目最终启用名单
vendor/mediatek/proprietary/scripts/soong/mtkcam/mtkcamvars.go  # tuning/IdxMgr/ISP 模块
```

**关键：metadata、tuning、sensorlist、lenslist、mtkcamvars.go 改动不在 MGK 范围内**，只编 MGK 不会更新这些参数，必须重编并刷入对应 Vendor/Vext 产品镜像。

## 3. 编译前后的一致性检查 [已验证]

合入时四处配置必须一致，避免“HAL 有、Kernel 没有”或“Kernel 编了、tuning 没编”：

```text
CameraConfig.mk   → CUSTOM_HAL_IMGSENSOR / CUSTOM_KERNEL_IMGSENSOR / CUSTOM_*_MAIN*_IMGSENSOR
ProjectConfig.mk  → CUSTOM_HAL_IMGSENSOR / CUSTOM_KERNEL_IMGSENSOR
defconfig         → CONFIG_CUSTOM_KERNEL_IMGSENSOR
BUILD.bazel       → config_cust_kernel_imgsensor
```

快速检查：

```bash
grep -R "CUSTOM_HAL_IMGSENSOR" device/mediatek/mt6789/
grep -R "CONFIG_CUSTOM_KERNEL_IMGSENSOR" kernel_device_modules-6.12/arch/arm64/configs/
grep -Rni "<sensor>" kernel_device_modules-6.12 device/mediatek vendor/mediatek/proprietary device/mediateksample
```

## 4. Patch 管理（防止丢文件）[已验证]

新 sensor 目录（driver/metadata/tuning）在 git 里是 **untracked**，`git diff` 默认不包含！只保存 `git diff` 的 patch 会漏掉整个驱动。

正确保存：

```bash
git add -A
git diff --cached --binary > camera-<sensor>.patch
grep "^diff --git" camera-<sensor>.patch   # 必须看到新目录里的文件
git apply --check camera-<sensor>.patch
```

导入：

```bash
git status && git apply --check camera-<sensor>.patch && git apply camera-<sensor>.patch
git status
grep -Rni "<sensor>_mipi_raw" kernel_device_modules-6.12 device/mediatek vendor/mediateksample
```

## 5. 编译验证顺序 [已验证]

1. Kernel 修改（驱动/DTS/上电/SensorList/Bazel）→ 编 MGK → `strings imgsensor_isp6s.ko | grep <sensor>`
2. Device/Vendor 修改 → 编 Vendor/Vext 镜像 → 刷机
3. 开机检查：KO 加载 → power on → MCLK/RST/电压 → I2C ACK/ID → HAL 枚举 MAIN/SUB/MAIN2 → 分辨率/方向/颜色/曝光/对焦
