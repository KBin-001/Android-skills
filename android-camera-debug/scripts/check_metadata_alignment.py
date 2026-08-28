#!/usr/bin/env python3
"""Android Camera Debug — Metadata 尺寸对齐检查 (Python3, 跨平台)

用途：从 Sensor metadata 头文件中提取声明的宽高尺寸，检查奇偶/对齐约束
      （YUV420 需偶数，平台 HEIF/C2 Encoder 常需 16 对齐），并给出修改建议。
      该检查来源于 S5K3M5SX HEIF 分辨率降级案例（见 references/metadata-tuning.md）。

用法：
  python check_metadata_alignment.py <config_static_metadata_project.h> [对齐粒度]
  例：python check_metadata_alignment.py config_static_metadata_project.h 16

退出码：0 = 所有尺寸合法；1 = 存在奇数/不对齐尺寸。
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
    # 将每个 CONFIG_ENTRY_VALUE 的注释并入下一行逻辑：这里简化处理，
    # 按格式标签 + 连续数字对 解析。
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
            # 兼容没有注释的写法：连续两个数字（前一个作为 width 暂存）
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
    # 尾部未闭合
    if pending_w is not None:
        results.append((fmt or "?", pending_w, None))
    return results


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    path = Path(sys.argv[1])
    align = int(sys.argv[2]) if len(sys.argv) > 2 else 16
    if not path.exists():
        print(f"文件不存在: {path}")
        sys.exit(2)

    sizes = extract_sizes(path)
    if not sizes:
        print("未解析到任何尺寸条目，请人工核对文件格式。")
        sys.exit(0)

    print(f"检查文件: {path}  对齐粒度: {align}")
    print(f"{'FORMAT':<24}{'W':>8}{'H':>8}   {'W%align':>8}{'H%align':>8}  状态")
    print("-" * 78)
    bad = 0
    for fmt, w, h in sizes:
        if w is None or h is None:
            print(f"{fmt:<24}{w!s:>8}{h!s:>8}   {'-':>8}{'-':>8}   [未知]")
            bad += 1
            continue
        w_odd = w % 2 != 0
        h_odd = h % 2 != 0
        w_a = w % align != 0
        h_a = h % align != 0
        issues = []
        if w_odd or h_odd:
            issues.append("奇数(违反YUV420)")
        if w_a or h_a:
            issues.append(f"非{align}对齐")
        status = "OK" if not issues else "⚠ " + " + ".join(issues)
        if issues:
            bad += 1
            sugg_w = (w + align - 1) // align * align
            sugg_h = (h + align - 1) // align * align
            if sugg_w != w or sugg_h != h:
                status += f"  → 建议 {sugg_w}x{sugg_h}"
        print(f"{fmt:<24}{w:>8}{h:>8}   {w_a!s:>8}{h_a!s:>8}  {status}")
    print("-" * 78)
    if bad:
        print(f"结论: {bad} 组尺寸不符合约束 ❌ — 参考 references/metadata-tuning.md 修改"
              f"（BLOB 与 YCbCr_420_888 需同步改）")
        sys.exit(1)
    print("结论: 所有尺寸符合约束 ✅")
    sys.exit(0)


if __name__ == "__main__":
    main()
