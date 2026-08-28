#!/usr/bin/env bash
# Android LCD Debug — 显示配置一致性检查脚本 (bash)
# 用途：给定 panel 关键字，自动搜索代码树，检查 panel 驱动/DTS/LK2/上层配置的一致性。
#      不依赖固定平台路径（自动适配 MT6789/MT8781/MT8391、Kernel 6.x）。
# 用法：./check_display_consistency.sh <panel_keyword> [source_root]
# 例  ：./check_display_consistency.sh jt132wql018 /path/to/mt8781-a17
#       ./check_display_consistency.sh lmibe127119272   # 缺省在当前目录搜索
# 注意：在 Linux/WSL 编译环境中运行；代码树根目录缺省为当前目录。
# 退出码：0 = 全部通过；1 = 存在缺失/不一致；2 = 用法错误。

set -u

if [ $# -lt 1 ]; then
    echo "Usage: $0 <panel_keyword> [source_root]" >&2
    echo "  panel_keyword  如 jt132wql018 / lmibe127119272 / nt37801" >&2
    echo "  source_root    代码树根目录（缺省为当前目录）" >&2
    exit 2
fi

PANEL="$1"
ROOT="${2:-$(pwd)}"
if [ ! -d "$ROOT" ]; then
    echo "错误：代码树根目录不存在: $ROOT" >&2
    exit 2
fi

echo "=== 检查 panel: $PANEL @ $ROOT ==="
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

# ---------- 1) Kernel panel 驱动 ----------
PANEL_DRV=$(find "$ROOT" -type f -name "*$PANEL*" -path "*drm/panel*" 2>/dev/null | head -1)
if [ -n "$PANEL_DRV" ]; then
    echo "  [OK]   Kernel panel driver: ${PANEL_DRV#$ROOT/}"
else
    echo "  [MISS] Kernel panel driver (drm/panel 下未找到 $PANEL)"
    FAIL=1
fi

# ---------- 2) DTS panel 节点 / lcm-params ----------
DTS_HITS=$(find "$ROOT" -type f \( -name "*.dts" -o -name "*.dtsi" \) 2>/dev/null | xargs grep -li "$PANEL" 2>/dev/null | head -3)
if [ -n "$DTS_HITS" ]; then
    while IFS= read -r dt; do
        echo "  [OK]   DTS 引用: ${dt#$ROOT/}"
    done <<< "$DTS_HITS"
else
    warn "未找到引用 $PANEL 的 dts/dtsi（跳过 DTS 检查）"
fi

# lcm-params 是否存在（现代 MTK 结构）
LCM_PARAMS=$(find "$ROOT" -type f -name "*.dtsi" 2>/dev/null | xargs grep -l "lcm-params" 2>/dev/null | head -1)
if [ -n "$LCM_PARAMS" ]; then
    echo "  [OK]   lcm-params 结构存在: ${LCM_PARAMS#$ROOT/}"
else
    warn "未找到 lcm-params（若为旧平台 LCM 结构可忽略）"
fi

# ---------- 3) LK2 LCM 目录 ----------
LK2_LCM=$(find "$ROOT" -type d -name "*$PANEL*" -path "*lk2*" 2>/dev/null | head -1)
if [ -n "$LK2_LCM" ]; then
    echo "  [OK]   LK2 LCM dir: ${LK2_LCM#$ROOT/}"
else
    warn "未找到 LK2 LCM 目录（LK2 侧可能未同步，注意 LK/Kernel 一致性）"
fi

# ---------- 4) 分辨率一致性（panel 驱动 vs 上层） ----------
# 提取 panel 驱动中声明的分辨率
if [ -n "$PANEL_DRV" ]; then
    RES=$(grep -oE "(1600|1920|1080|1440|2400|3200|1200|800)[xX×](1600|1920|1080|1440|2400|3200|1200|800)" "$PANEL_DRV" 2>/dev/null | sort -u | head -5)
    if [ -n "$RES" ]; then
        echo "  [INFO] panel 驱动中出现的分辨率: $(echo $RES | tr '\n' ' ')"
    fi
fi

# ---------- 5) backlight / PWM 配置 ----------
BL=$(find "$ROOT" -type f -name "*.dtsi" 2>/dev/null | xargs grep -l "pwm-leds\|lcd-backlight\|disp_pwm" 2>/dev/null | head -1)
if [ -n "$BL" ]; then
    echo "  [OK]   背光 PWM 配置: ${BL#$ROOT/}"
else
    warn "未找到背光 PWM 配置（若无背光需求可忽略）"
fi

# ---------- 6) 偏压 IC / 电源 ----------
BIAS=$(find "$ROOT" -type f \( -name "*.dts" -o -name "*.dtsi" \) 2>/dev/null | xargs grep -li "aw37503\|ocp2138\|vdd1v8-supply\|avdd-gpios\|avee-gpios" 2>/dev/null | head -1)
if [ -n "$BIAS" ]; then
    echo "  [OK]   偏压/电源配置: ${BIAS#$ROOT/}"
else
    warn "未找到偏压/电源配置（若无偏压 IC 可忽略）"
fi

# ---------- 7) 上层显示配置（DPI/方向/物理尺寸） ----------
UP=$(find "$ROOT" -type f -name "*.mk" 2>/dev/null | xargs grep -li "MTK_LCM_PHYSICAL_ROTATION\|ro.sf.lcd_density" 2>/dev/null | head -1)
if [ -n "$UP" ]; then
    echo "  [OK]   上层显示配置: ${UP#$ROOT/}"
else
    warn "未找到上层显示配置（DPI/方向）"
fi

echo "---"
if [ "$FAIL" -eq 0 ]; then
    echo "RESULT: 关键项全部通过 ✅$([ "$WARN" -eq 1 ] && echo '（有 WARN，见上）')"
else
    echo "RESULT: 存在缺失 ❌ — 按 [MISS] 项补齐（参考 references/display-architecture.md）"
fi
exit $FAIL
