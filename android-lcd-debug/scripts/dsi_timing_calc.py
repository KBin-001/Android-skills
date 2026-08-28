#!/usr/bin/env python3
"""Android LCD Debug — DSI Timing 计算器 (Python3, 跨平台)

用途：从 panel datasheet 的 timing 参数计算 Htotal/Vtotal/PCLK，
      以及动态刷新率场景下保持 PCLK 不变所需的新 Vtotal/VFP。
      该计算来源于 JT132WQL018 90Hz→45Hz 动态刷新率案例（references/dsi-timing.md）。

用法:
  python dsi_timing_calc.py --hac 1600 --hfp 60 --hsa 20 --hbp 40 \
      --vac 2400 --vfp 270 --vsa 8 --vbp 38 --fps 90 [--new-fps 45]

退出码：0 = 正常；2 = 用法错误。
"""
import argparse


def calc(hac, hfp, hsa, hbp, vac, vfp, vsa, vbp, fps):
    htotal = hac + hfp + hsa + hbp
    vtotal = vac + vfp + vsa + vbp
    pclk = htotal * vtotal * fps
    print(f"Htotal = {hac}+{hfp}+{hsa}+{hbp} = {htotal}")
    print(f"Vtotal = {vac}+{vfp}+{vsa}+{vbp} = {vtotal}")
    print(f"PCLK   = {htotal} x {vtotal} x {fps} = {pclk:,} Hz ≈ {pclk/1e6:.1f} MHz")
    return htotal, vtotal, pclk


def main():
    p = argparse.ArgumentParser(description="DSI timing 计算器")
    p.add_argument("--hac", type=int, required=True, help="水平有效像素")
    p.add_argument("--hfp", type=int, required=True, help="水平前肩")
    p.add_argument("--hsa", type=int, required=True, help="水平同步")
    p.add_argument("--hbp", type=int, required=True, help="水平后肩")
    p.add_argument("--vac", type=int, required=True, help="垂直有效像素")
    p.add_argument("--vfp", type=int, required=True, help="垂直前肩")
    p.add_argument("--vsa", type=int, required=True, help="垂直同步")
    p.add_argument("--vbp", type=int, required=True, help="垂直后肩")
    p.add_argument("--fps", type=float, required=True, help="当前刷新率(Hz)")
    p.add_argument("--new-fps", type=float, default=None, help="目标刷新率(Hz)，计算所需 Vtotal/VFP")
    args = p.parse_args()

    htotal, vtotal, pclk = calc(
        args.hac, args.hfp, args.hsa, args.hbp,
        args.vac, args.vfp, args.vsa, args.vbp, args.fps)

    if args.new_fps:
        if args.new_fps <= 0:
            print("错误: --new-fps 必须为正数", file=sys.stderr)
            return 2
        vtotal_new = pclk / (htotal * args.new_fps)
        vfp_new = vtotal_new - args.vac - args.vsa - args.vbp
        print(f"\n目标 {args.new_fps:g}Hz (保持 PCLK 不变):")
        print(f"  Vtotal_{args.new_fps:g} = {pclk:,} / ({htotal} x {args.new_fps:g}) = {vtotal_new:,.0f} 行")
        print(f"  VFP_{args.new_fps:g}    = {vtotal_new:,.0f} - {args.vac} - {args.vsa} - {args.vbp} = {vfp_new:,.0f}")
        print(f"\n  → kernel panel: .vfp_low_power = {vfp_new:,.0f}")
        print(f"  → 验证 PCLK 一致性: {htotal} x {vtotal_new:,.0f} x {args.new_fps:g} = {htotal*vtotal_new*args.new_fps:,.0f} Hz")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
