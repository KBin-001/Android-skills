# 背光 PWM（Backlight PWM）

> 分层：通用 + MTK 平台规则；核心案例 JT132WQL018（GPIO84 DISP_PWM）[已验证]

## 1. 背光信号必须分开理解 [已验证]

| 信号 | 作用 | 控制方式 |
|---|---|---|
| `DISP_PWM` | PWM 占空比决定亮度 | GPIO 复用为 PWM，由 PWM framework 控制 |
| `LCM_LED_EN` | 背光电源/背光 IC 总使能 | pinctrl 高低或专用 GPIO |

**核心坑**：PWM 引脚（如 GPIO84）进入 Kernel 后应工作在 `func1/DISP_PWM` 模式，不是普通 GPIO。GPIO12（EN）即使为高，GPIO84 duty=0 时背光仍可能熄灭。**两者不能混为一个 GPIO。**

## 2. DTS 配置示例 [已验证]

```dts
&mtk_leds {
	compatible = "mediatek,pwm-leds";
	backlight {
		label = "lcd-backlight";
		led-mode = <5>;
		pwm_config = <0 1 0 0 0>;
		pwms = <&disp_pwm 0 39385>;   // period 39385ns ≈ 25.39kHz
		pwm-names = "lcd-backlight";
	};
};

&disp_pwm {
	pinctrl-names = "default";
	pinctrl-0 = <&disp_pwm_pin>;
	status = "okay";
};

&pio {
	disp_pwm_pin: disp_pwm_pin {
		pins_cmd_dat {
			pinmux = <PINMUX_GPIO84__FUNC_DISP_PWM>;
		};
	};
	mtkfb_pins_lcm_led_en1: lcm_led_en1_gpio {
		pins_cmd_dat {
			pinmux = <PINMUX_GPIO12__FUNC_GPIO12>;
			output-high;
		};
	};
};
```

- `compatible = "mediatek,pwm-leds"` → 匹配 `leds-mtk-pwm.c`。
- panel DTS 节点若不配 `backlight` phandle，`ctx->backlight` 为空，外部背光完全走 MTK LED/PWM 路径。
- DCS `0x51` 是 panel 内部 DCS 亮度通道，与外部 GPIO PWM **是两条不同路径**。

## 3. 亮度下发链路 [已验证]

```text
Framework/SurfaceFlinger 设置亮度
  → LED class: mtk_set_brightness()
  → mtk_set_hw_brightness()   // 逻辑亮度映射为硬件亮度
  → led_pwm_set()             // duty = period × brightness / max_hw_brightness
  → pwm_apply_might_sleep()
  → pwm-mtk-disp → GPIO84 输出 PWM
```

核心逻辑：

```c
duty = pwmstate.period;
duty *= brightness;
do_div(duty, max_hw_brightness);
pwmstate.duty_cycle = duty;
pwmstate.enabled = duty > 0;
pwm_apply_might_sleep(pwm, &pwmstate);
```

## 4. 三层状态模型 [已验证]

```text
Framework logical brightness  (L:104)
  ≠  LED driver hw_brightness (map:835)
  ≠  PWM controller duty/波形 (duty:0)
```

调试必须逐层确认。日志中只有 `Set lcd-backlight L:104 map:835` 但缺 `set hw brightness` 和 `pwm_apply`，说明请求到达 LED 层但没提交硬件。

## 5. 息屏唤醒不亮（AAL 恢复坑）[已验证]

现象：唤醒后 panel 重新 init（`jdi_prepare → init complete → jdi_enable`），逻辑亮度恢复非零，但 PWM duty 仍为 0。

根因：MTK LED 框架 AAL 开启时负责提交硬件亮度；灭屏时 PWM 被写 0，唤醒时旧逻辑未保证第一次非零亮度一定写到硬件。

修复（`drivers/leds/leds-mtk.c` 的 `mtk_set_brightness()`）：

```c
if (!led_conf->aal_enable ||
    (trans_level > 0 && led_dat->hw_brightness == 0)) {
    if (led_conf->aal_enable)
        pr_info("restore %s after resume: 0 -> %d", ...);
    mtk_set_hw_brightness(led_dat, trans_level, 0, 1 << SET_BACKLIGHT_LEVEL);
    led_dat->last_hw_brightness = trans_level;
}
```

修复后完整链：`logical 104 → hw 835 → duty 16065ns → pwm_apply`。

## 6. 标准调试步骤 [已验证]

1. **区分无图 vs 无背光**：`adb shell screencap`；截图正常屏黑 = 背光；强光见暗图 = 背光；截图也黑 = 上层。
2. **确认驱动与节点**：`lsmod | grep -E 'panel|leds_mtk|pwm'`；`/sys/class/leds/lcd-backlight/` 存在；`cat max_brightness/brightness`。
3. **确认 pinmux**：`grep -i 'pin 84' /sys/kernel/debug/pinctrl/*/pinmux-pins` → `function func1 group GPIO84`（`GPIO UNCLAIMED` 正常，表示交给 PWM 而非 GPIO 子系统）。
4. **确认 PWM 状态**：`cat /sys/kernel/debug/pwm` → 亮屏 duty>0，灭屏 duty=0。
5. **手动验证 LED class**：`echo 0/100 > /sys/class/leds/lcd-backlight/brightness` 后看 duty 是否变化。
6. **抓唤醒日志**：`dmesg -w | findstr /i "jdi_ lcd-backlight leds_mtk pwm duty restore"`，按「灭屏→0 / 唤醒→非零→pwm_apply」核对。
7. **检查独立 EN**：GPIO12 电平、`/sys/kernel/debug/gpio`；实测 EN 先恢复再允许 PWM。
8. **示波器实测**：GPIO84 频率/占空比、GPIO12 EN 电平。

## 7. 试错记录 [已验证]

- 把 GPIO84 当普通 GPIO 拉高（LK 阶段可临时常高，Kernel 后必须交 PWM）。
- 只看 `jdi_enable- enabled=1`（只证明 panel 状态，不证明 PWM 输出）。
- 看到逻辑亮度非零就认为背光恢复。
- 把 `GPIO UNCLAIMED` 当错误。
- 只改 panel DCS `0x51`（无法替代 GPIO84 PWM 输出）。

## 8. 亮度曲线调整（高亮段压缩）[已验证]

`drivers/leds/leds-mtk.c` 中 `brightness_remap_highlight()`：

```c
knee    = input_max * 70 / 100;   // 0~70% 保持线性
out_max = input_max * 830 / 1000; // 高亮段压缩到 83%（注意注释可能写 85.5%，以代码为准）
// level > knee: 线性压缩 [knee, input_max] → [knee, out_max]
```

- 在 `brightness_maptolevel()` 中接入 remap，`mtk_leds_brightness_set()` 用转换后值下发。
- 注意 `last_hw_brightness` 现在记录的是**转换后的实际硬件亮度**，不是原始输入。
- ⚠️ 注释与代码可能不一致（85.5% vs 83%），以代码实际计算值为准。
