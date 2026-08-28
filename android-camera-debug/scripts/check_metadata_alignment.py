#!/usr/bin/env python3
"""Android Camera Debug — Metadata 尺寸对齐检查 (Python3, 跨平台)

用途：从 Sensor metadata 头文件中提取声明的宽高尺寸，检查约束。
      该检查来源于 S5K3M5SX HEIF 分辨率降级案例（见 references/metadata-tuning.md）。

判定分级（不要把案例经验升级成所有 Camera metadata 的硬规则）:
  - 奇数尺寸       -> ERROR（YUV420 色度采样要求偶数，属于通用硬约束）
  - 非 16 对齐     -> WARN（仅提示；只有确认平台 HEIF/C2 Encoder 存在 16 对齐
                      约束时才需要修，例如 S5K3M5SX HEIF 案例）
  - 默认退出码只受 ERROR 影响；用 --strict-align 可将非 16 对齐也判为 ERROR
    （用于已知 HEIF/C2 约束的目标平台）

用法:
  python check_metadata_alignment.py <config_static_metadata_project.h> [--align N] [--strict-align]
  例：python check_metadata_alignment.py config_static_metadata_project.h
      python check_metadata_alignment.py config_static_metadata_project.h --align 16 --strict-align

退出码：0 = 无 ERROR；1 = 存在 ERROR；2 = 用法错误。
"""
import re
import sys
from pathlib import Path


def extract_sizes(path: Path):
    """抓取 CONFIG_ENTRY_VALUE 块中的 (format, width, height) 序列。

    匹配形如：
      CONFIG_ENTRY_VALUE(HAL_PIXEL_FORMAT_BLOB, MINT64) //13mp 3:2
      CONFIG_ENTRY_VALUE(4415, MINT64)        // width
      CONFIG_ENTRY_VALUE(2943, MINT64)        // height
    """
    text = path.read_text(encoding="utf-8", errors="replace")
    results = []
    lines = text.splitlines()
    fmt = None
    pending_w = None
    for line in lines:
        mfmt = re.search(r"CONFIG_ENTRY_VALUE\(HAL_PIXEL_FORMAT_([A-Za-z0-9_]+)", line)
        if mfmt:
            fmt = mfmt.group(1)
            continue
        mw = re.search(r"CONFIG_ENTRY_VALUE\((\d+), MINT64\).*//\s*(width|height)\b", line, re.I)
        if not mw:
            mn = re.search(r"CONFIG_ENTRY_VALUE\((\d+), MINT64\)", line)
            if not mn:
                continue
            if pending_w is None:
                pending_w = int(mn.group(1))
                continue
            w, h = pending_w, int(mn.group(1))
            pending_w = None
            results.append((fmt or "?", w, h))
            continue
        val = int(mw.group(1))
        if mw.group(2).lower() == "width":
            pending_w = val
        else:
            if pending_w is not None:
                results.append((fmt or "?", pending_w, val))
                pending_w = None
    if pending_w is not None:
        results.append((fmt or "?", pending_w, None))
    return results


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)

    path = Path(sys.argv[1])
    align = 16
    strict_align = False
    rest = sys.argv[2:]
    i = 0
    while i < len(rest):
        if rest[i] == "--align" and i + 1 < len(rest):
            align = int(rest[i + 1])
            i += 2
        elif rest[i] == "--strict-align":
            strict_align = True
            i += 1
        else:
            print(f"未知参数: {rest[i]}", file=sys.stderr)
            sys.exit(2)

    if not path.exists():
        print(f"文件不存在: {path}")
        sys.exit(2)

    sizes = extract_sizes(path)
    if not sizes:
        print("未解析到任何尺寸条目，请人工核对文件格式。")
        sys.exit(0)

    mode = "STRICT(16对齐视为ERROR)" if strict_align else "默认(非16对齐仅WARN)"
    print(f"检查文件: {path}   对齐粒度: {align}   模式: {mode}")
    print(f"{'FORMAT':<24}{'W':>8}{'H':>8}   {'W%align':>8}{'H%align':>8}  状态")
    print("-" * 78)
    errors = 0
    warns = 0
    for fmt, w, h in sizes:
        if w is None or h is None:
            print(f"{fmt:<24}{w!s:>8}{h!s:>8}   {'-':>8}{'-':>8}   [未知]")
            errors += 1
            continue
        odd = (w % 2 != 0) or (h % 2 != 0)
        misaligned = (w % align != 0) or (h % align != 0)
        w_a = w % align != 0
        h_a = h % align != 0

        if odd:
            status = "ERROR: 奇数尺寸(违反YUV420偶数约束)"
            errors += 1
            sugg_w = (w + 1) // 2 * 2
            sugg_h = (h + 1) // 2 * 2
            if (sugg_w != w) or (sugg_h != h):
                status += f"  → 偶数建议 {sugg_w}x{sugg_h}"
        elif misaligned:
            if strict_align:
                status = f"ERROR: 非{align}对齐(strict模式)"
                errors += 1
                sugg_w = (w + align - 1) // align * align
                sugg_h = (h + align - 1) // align * align
                if (sugg_w != w) or (sugg_h != h):
                    status += f"  → 建议 {sugg_w}x{sugg_h}"
            else:
                status = f"WARN: 非{align}对齐(仅提示; 确认 HEIF/C2 约束后再修)"
                warns += 1
        else:
            status = "OK"

        print(f"{fmt:<24}{w:>8}{h:>8}   {str(w_a):>8}{str(h_a):>8}  {status}")
    print("-" * 78)
    if errors:
        print(f"结论: {errors} 组 ERROR ❌ — 参考 references/metadata-tuning.md 修改"
              f"（BLOB 与 YCbCr_420_888 需同步改）")
        sys.exit(1)
    if warns:
        print(f"结论: 无 ERROR ✅，但有 {warns} 组 WARN"
              f" — 仅当目标平台确认存在 {align} 对齐约束时用 --strict-align 复核")
        sys.exit(0)
    print("结论: 所有尺寸符合约束 ✅")
    sys.exit(0)


if __name__ == "__main__":
    main()
