# Android Camera Debug — 一致性检查脚本 (bash)
# 用途：给定 sensor 名，检查 Kernel/Vendor/Device/Build 各处的注册一致性。
# 用法：./check_sensor_consistency.sh <sensor_name> [代码树根目录]
# 例  ：./check_sensor_consistency.sh gc08a8_mipi_raw /path/to/mt8781-a17
# 注意：在 Linux/WSL 编译环境中运行；代码树根目录缺省为当前目录。
# 退出码：0 = 全部通过；1 = 存在缺失/不一致。

set -u

SENSOR="$1"
ROOT="${2:-$(pwd)}"

# sensor 名转宏：gc08a8_mipi_raw -> GC08A8_MIPI_RAW
MACRO=$(echo "$SENSOR" | sed 's/_mipi_raw$//' | tr '[:lower:]' '[:upper:]')_MIPI_RAW
SNAME=$(echo "$SENSOR" | sed 's/_mipi_raw$//' | tr '[:lower:]' '[:upper:]')

echo "=== 检查 sensor: $SENSOR (macro: $MACRO) @ $ROOT ==="
FAIL=0

check() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "  [OK]   $label"
  else
    echo "  [MISS] $label"
    FAIL=1
  fi
}

# 1) Kernel 驱动目录
check "Kernel driver dir" \
  test -d "$ROOT/kernel_device_modules-6.12/drivers/misc/mediatek/imgsensor/src/common/v1_1/$SENSOR"

# 2) Kernel kd_imgsensor.h ID + DRVNAME
check "Kernel kd_imgsensor.h: DRVNAME" \
  grep -q "SENSOR_DRVNAME_${SNAME}_MIPI_RAW" \
    "$ROOT/kernel_device_modules-6.12/drivers/misc/mediatek/imgsensor/inc/kd_imgsensor.h"
check "Kernel kd_imgsensor.h: ID" \
  grep -q "${SNAME}_SENSOR_ID" \
    "$ROOT/kernel_device_modules-6.12/drivers/misc/mediatek/imgsensor/inc/kd_imgsensor.h"

# 3) Device 侧 kd_imgsensor.h 副本
check "Device kd_imgsensor.h 副本" \
  grep -q "SENSOR_DRVNAME_${SNAME}_MIPI_RAW" \
    "$ROOT/device/mediatek/vendor/camera/kernel-headers/kd_imgsensor.h"

# 4) Kernel SensorList 注册
check "imgsensor_sensor_list.c 注册" \
  grep -q "SENSOR_DRVNAME_${SNAME}_MIPI_RAW" \
    "$ROOT/kernel_device_modules-6.12/drivers/misc/mediatek/imgsensor/src/common/v1_1/imgsensor_sensor_list.c"

# 5) defconfig
check "defconfig CONFIG_CUSTOM_KERNEL_IMGSENSOR" \
  grep -q "$SENSOR" "$ROOT/kernel_device_modules-6.12/arch/arm64/configs/"*.defconfig

# 6) BUILD.bazel
check "BUILD.bazel config_cust_kernel_imgsensor" \
  grep -q "$SENSOR" "$ROOT/kernel_device_modules-6.12/drivers/misc/mediatek/imgsensor/src/BUILD.bazel"

# 7) Vendor HAL sensorlist.cpp (common + tablet)
check "HAL sensorlist.cpp (common)" \
  grep -q "$SENSOR" "$ROOT/vendor/mediatek/proprietary/custom/common/hal/imgsensor_src/sensorlist.cpp"
check "HAL sensorlist.cpp (tablet)" \
  grep -q "$SENSOR" "$ROOT/vendor/mediatek/proprietary/custom/mt6789/hal/imgsensor_src/tablet/sensorlist.cpp"

# 8) CameraConfig.mk / ProjectConfig.mk
check "CameraConfig.mk" \
  grep -q "$SENSOR" "$ROOT/device/mediatek/mt6789/CameraConfig.mk"
check "ProjectConfig.mk" \
  grep -q "$SENSOR" "$ROOT/device/mediateksample/"*/ProjectConfig.mk

# 9) Metadata 目录（四套）
for meta in \
  "vendor/mediatek/proprietary/custom/common/hal/imgsensor_metadata/sensor/$SENSOR" \
  "vendor/mediatek/proprietary/custom/common/legacy/hal/imgsensor_metadata/sensor/$SENSOR" \
  "vendor/mediatek/proprietary/custom/mt6789/hal/imgsensor/ver1/$SENSOR" \
  "vendor/mediatek/proprietary/custom/mt6789/hal/imgsensor_metadata/$SENSOR"; do
  check "Metadata dir: $(basename "$(dirname "$meta")")/$(basename "$meta")" \
    test -d "$ROOT/$meta"
done

# 10) DTS enable_sensor
check "DTS cam*_enable_sensor" \
  grep -q "\"$SENSOR\"" "$ROOT/kernel_device_modules-6.12/arch/arm64/boot/dts/mediatek/cust_mt6789_camera.dtsi"

# 11) Sensor ID 一致性提示（不判定失败，只报告）
echo "---"
echo "Sensor ID 定义位置（手动核对一致性）:"
grep -Rni "${SNAME}_SENSOR_ID" \
  "$ROOT/kernel_device_modules-6.12/drivers/misc/mediatek/imgsensor" \
  "$ROOT/device/mediatek/vendor/camera" 2>/dev/null \
  | grep -v Binary | head -10 || echo "  (未找到 ID 定义)"

echo "---"
if [ "$FAIL" -eq 0 ]; then
  echo "RESULT: 全部通过 ✅"
else
  echo "RESULT: 存在缺失 ❌ — 按上面 [MISS] 项补齐（参考 references/mtk-camera-architecture.md）"
fi
exit $FAIL
