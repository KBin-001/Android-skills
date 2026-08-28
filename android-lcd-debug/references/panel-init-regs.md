# Panel 初始化寄存器（init sequence / vendor regs）

> 分层：通用 + 项目已验证案例（LMIBE127119272 色彩参数）

## 1. MIPI DSI 命令格式 [已验证]

屏厂给的命令通常形如：

```c
MIPI_WR(0x39, 0xBD, 0x00);
MIPI_WR(0x39, 0xC1, 0x01);
```

**坑**：第一个 `0x39` 是 MIPI DSI packet type（long write），不是寄存器。LK/kernel 的写接口已封装 DSI packet，真正要写的是后面的寄存器和数据。**不要把它当寄存器写进去。**

## 2. 寄存器页切换（page select）[已验证]

某些 panel 用 page/bank select 寄存器分页存放参数：

```text
0xBD = 切换寄存器页 (page select)
0xC1 = 当前页下的色彩参数表
```

**BD 和 C1 的顺序必须保留**：不能只拷贝 C1，也不能把多页参数混在一起。示例（三页色彩参数）：

```text
BD 0x00 → C1 0x01...
BD 0x01 → C1 58字节...
BD 0x02 → C1 58字节...
BD 0x03 → C1 58字节...
BD 0x00 (回到默认页)
```

## 3. 合入位置 [已验证]

- **LK2**：放入 `lcm_init_setting[]`（`{0xBD, 1, {0x00}}, {0xC1, 1, {0x01}}, ...`）。
- **Kernel**：放入 panel 驱动的 init 函数（如 `lmibe127119272_panel_init()`），用 `dcs_write_seq_static(ctx, reg, data...)`。
- **放置位置**：建议在原始初始化参数末尾、锁寄存器命令（如 `B9 00 00 00 00`）之前、`0x11 Sleep Out` 和 `0x29 Display On` 之前。

## 4. 色彩/色温/饱和度本质 [已验证]

屏厂给的色彩/色温/饱和度参数，本质是写 panel IC 的 vendor 寄存器，**不是**改 Android 上层显示效果，也**不是**改 DRM color matrix。合入位置应在 LCM 初始化 DSI 命令里（LK 的 `lcm_init_setting[]` 和 kernel 的 panel_init）。

## 5. 通用 init sequence 注意事项 [已验证/待验证]

- `0x11` Sleep Out 与 `0x29` Display On 之间的顺序通常不可交换。
- init 序列要区分「上电后首次」与「唤醒恢复」：suspend/resume 时通常不需要重发全部 init code，只发 sleep in/out + display off/on。
- 时序命令（如 `0x35` Tear On）按 panel datasheet 要求。
- 多页寄存器参数合入时，用 page 顺序逐页写入，页间切换命令必须成对。
