#!/usr/bin/env bash
# Android Camera Debug — 一致性检查脚本 (bash)
# 用途：给定 sensor 名，自动搜索代码树，检查 Kernel/Vendor/Device/Build 各处的注册一致性。
#      不依赖固定平台路径（自动适配 MT6789/MT8781/MT8391、Kernel 6.1/6.12 等不同代码树）。
# 用法：./check_sensor_consistency.sh <sensor_name> [source_root]
# 例  ：./check_sensor_consistency.sh gc08a8_mipi_raw /path/to/mt8781-a17
#       ./check_sensor_consistency.sh gc08a8_mipi_raw   # 缺省在当前目录搜索
# 注意：在 Linux/WSL 编译环境中运行；代码树根目录缺省为当前目录。
# 退出码：0 = 全部通过；1 = 存在缺失/不一致；2 = 用法错误。

set -u

if [ $# -lt 1 ]; then
    echo "Usage: $0 <sensor_name> [source_root]" >&2
    echo "  sensor_name  如 gc08a8_mipi_raw" >&2
    echo "  source_root  代码树根目录（缺省为当前目录）" >&2
    exit 2
fi

SENSOR="$1"
ROOT="${2:-$(pwd)}"
if [ ! -d "$ROOT" ]; then
    echo "错误：代码树根目录不存在: $ROOT" >&2
    exit 2
fi

# sensor 名转宏：gc08a8_mipi_raw -> GC08A8_MIPI_RAW
STEM=$(echo "$SENSOR" | sed 's/_mipi_raw$//')
SNAME=$(echo "$STEM" | tr '[:lower:]' '[:upper:]')
MACRO="${SNAME}_MIPI_RAW"

echo "=== 检查 sensor: $SENSOR (macro: $MACRO) @ $ROOT ==="
FAIL=0
WARN=0

check() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "  [OK]   $label"
    else
        echo "  [MISS] $label"
        FAIL=1
    fi
}

warn() {
    echo "  [WARN] $1"
    WARN=1
}

# ---------- 1) Kernel 驱动目录（按文件名自动搜索，不限平台路径） ----------
KERNEL_DRV=$(find "$ROOT" -type d -name "$SENSOR" -path "*imgsensor*" 2>/dev/null | head -1)
if [ -n "$KERNEL_DRV" ]; then
    echo "  [OK]   Kernel driver dir: ${KERNEL_DRV#$ROOT/}"
else
    echo "  [MISS] Kernel driver dir: 未找到 imgsensor 下的 $SENSOR 目录"
    FAIL=1
fi

# ---------- 2) kd_imgsensor.h：ID + DRVNAME（Kernel 与 Device 所有副本） ----------
KD_HDRS=$(find "$ROOT" -type f -name "kd_imgsensor.h" 2>/dev/null | head -5)
if [ -z "$KD_HDRS" ]; then
    warn "未找到 kd_imgsensor.h（跳过 ID/DRVNAME 检查）"
else
    while IFS= read -r hdr; do
        name_ok=0; id_ok=0
        grep -q "SENSOR_DRVNAME_${SNAME}_MIPI_RAW" "$hdr" && name_ok=1
        grep -q "${SNAME}_SENSOR_ID" "$hdr" && id_ok=1
        if [ "$name_ok" -eq 1 ] && [ "$id_ok" -eq 1 ]; then
            echo "  [OK]   kd_imgsensor.h: ${hdr#$ROOT/}"
        else
            echo "  [MISS] kd_imgsensor.h: ${hdr#$ROOT/} (DRVNAME=$name_ok, ID=$id_ok)"
            FAIL=1
        fi
    done <<< "$KD_HDRS"
fi

# ---------- 3) Kernel SensorList 注册 ----------
SL_C=$(find "$ROOT" -type f -name "imgsensor_sensor_list.c" 2>/dev/null | head -1)
if [ -n "$SL_C" ]; then
    check "Kernel imgsensor_sensor_list.c 注册" grep -q "SENSOR_DRVNAME_${SNAME}_MIPI_RAW" "$SL_C"
else
    warn "未找到 imgsensor_sensor_list.c（跳过 Kernel SensorList 检查）"
fi

# ---------- 4) defconfig / BUILD.bazel（按内容搜索，不再按 6.12 固定路径） ----------
# 注意：MTK defconfig 文件名形如 mgk_64_k612_defconfig（下划线，无点），
#       用 -name "*defconfig" 而非 "*.defconfig"
DEFCFG=""
while IFS= read -r df; do
    if grep -q "CONFIG_CUSTOM_KERNEL_IMGSENSOR" "$df" 2>/dev/null; then
        DEFCFG="$df"
        break
    fi
done < <(find "$ROOT" -type f -name "*defconfig" 2>/dev/null)
if [ -n "$DEFCFG" ]; then
    check "defconfig: ${DEFCFG#$ROOT/}" grep -q "$SENSOR" "$DEFCFG"
else
    warn "未找到含 CONFIG_CUSTOM_KERNEL_IMGSENSOR 的 defconfig（跳过）"
fi

BAZEL=""
while IFS= read -r bz; do
    if grep -q "config_cust_kernel_imgsensor" "$bz" 2>/dev/null; then
        BAZEL="$bz"
        break
    fi
done < <(find "$ROOT" -type f -name "BUILD.bazel" 2>/dev/null)
if [ -n "$BAZEL" ]; then
    check "BUILD.bazel: ${BAZEL#$ROOT/}" grep -q "$SENSOR" "$BAZEL"
else
    warn "未找到含 config_cust_kernel_imgsensor 的 BUILD.bazel（跳过 Bazel 检查）"
fi

# ---------- 5) Vendor HAL sensorlist.cpp（common + tablet 等所有副本） ----------
# 注意：真实 sensorlist.cpp 里只有宏 SENSOR_DRVNAME_<SENSOR>_MIPI_RAW，
#       不会出现 "gc08a8_mipi_raw" 字符串，所以用宏名检查
SLISTS=$(find "$ROOT" -type f -name "sensorlist.cpp" -path "*imgsensor_src*" 2>/dev/null)
if [ -z "$SLISTS" ]; then
    warn "未找到 imgsensor_src 下的 sensorlist.cpp（跳过 HAL SensorList 检查）"
else
    while IFS= read -r sl; do
        check "HAL sensorlist.cpp: ${sl#$ROOT/}" grep -q "SENSOR_DRVNAME_${SNAME}_MIPI_RAW" "$sl"
    done <<< "$SLISTS"
fi

# ---------- 6) CameraConfig.mk / ProjectConfig.mk ----------
CAMCFG=$(find "$ROOT" -type f -name "CameraConfig.mk" 2>/dev/null | head -1)
if [ -n "$CAMCFG" ]; then
    check "CameraConfig.mk: ${CAMCFG#$ROOT/}" grep -q "$SENSOR" "$CAMCFG"
else
    warn "未找到 CameraConfig.mk（跳过）"
fi

PRJCFG=""
while IFS= read -r pc; do
    if grep -q "CUSTOM_HAL_IMGSENSOR" "$pc" 2>/dev/null; then
        PRJCFG="$pc"
        break
    fi
done < <(find "$ROOT" -type f -name "ProjectConfig.mk" 2>/dev/null)
if [ -n "$PRJCFG" ]; then
    check "ProjectConfig.mk: ${PRJCFG#$ROOT/}" grep -q "$SENSOR" "$PRJCFG"
else
    warn "未找到含 CUSTOM_HAL_IMGSENSOR 的 ProjectConfig.mk（跳过）"
fi

# ---------- 7) Metadata / Tuning 目录（按 sensor 名自动搜索） ----------
META_DIRS=$(find "$ROOT" -type d -name "$SENSOR" -path "*imgsensor_metadata*" 2>/dev/null)
if [ -z "$META_DIRS" ]; then
    warn "未找到 imgsensor_metadata/$SENSOR 目录（metadata 缺失风险）"
else
    while IFS= read -r md; do
        echo "  [OK]   Metadata dir: ${md#$ROOT/}"
    done <<< "$META_DIRS"
fi

VER1_DIRS=$(find "$ROOT" -type d -name "$SENSOR" -path "*imgsensor/ver1*" 2>/dev/null)
if [ -z "$VER1_DIRS" ]; then
    warn "未找到 imgsensor/ver1/$SENSOR 目录（tuning 缺失风险）"
else
    while IFS= read -r v1; do
        echo "  [OK]   Tuning dir: ${v1#$ROOT/}"
    done <<< "$VER1_DIRS"
fi

# ---------- 8) DTS enable_sensor（自动搜索 camera dtsi） ----------
DTS=""
while IFS= read -r dt; do
    if grep -q "enable_sensor" "$dt" 2>/dev/null; then
        DTS="$dt"
        break
    fi
done < <(find "$ROOT" -type f -name "*camera*.dtsi" 2>/dev/null)
if [ -n "$DTS" ]; then
    check "DTS enable_sensor: ${DTS#$ROOT/}" grep -q "\"$SENSOR\"" "$DTS"
else
    warn "未找到含 enable_sensor 的 camera dtsi（跳过 DTS 检查）"
fi

# ---------- 9) mtkcamvars.go（Soong 注册） ----------
MKVARS=$(find "$ROOT" -type f -name "mtkcamvars.go" 2>/dev/null | head -1)
if [ -n "$MKVARS" ]; then
    check "mtkcamvars.go: ${MKVARS#$ROOT/}" grep -q "$SENSOR" "$MKVARS"
else
    warn "未找到 mtkcamvars.go（跳过 Soong 检查）"
fi

# ---------- 10) Sensor ID 一致性提示（只报告不判定，人工核对） ----------
echo "---"
echo "Sensor ID 定义位置（人工核对 Kernel vs Vendor 是否一致，重点: 0x08a8 vs 0x08a3 教训）:"
grep -Rni "${SNAME}_SENSOR_ID" \
    "$ROOT"/kernel* "$ROOT"/device* "$ROOT"/vendor* 2>/dev/null \
    | grep -v Binary | head -10 || echo "  (未找到，可能路径结构不同，请人工搜索)"
echo "---"

if [ "$FAIL" -eq 0 ]; then
    echo "RESULT: 全部通过 ✅$([ "$WARN" -eq 1 ] && echo '（有 WARN，建议人工确认）' || true)"
else
    echo "RESULT: 存在缺失 ❌ — 按 [MISS] 项补齐（参考 references/mtk-camera-architecture.md）"
fi
exit $FAIL
