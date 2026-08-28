# 关机充电动画（KPOC）显示异常

> 分层：MTK 平台规则；核心案例 Z3 (MT8781, 1600x2400) [已验证]

## 1. KPOC 动画路径 [已验证]

关机充电不是普通 Android 窗口动画：

```text
充电状态 / Fuel Gauge
  → kpoc_charger
  → libshowlogo (vendor/mediatek/proprietary/external/libshowlogo)
  → 从 logo 分区读取并解压 BMP
  → Framebuffer / DRM 显示
```

排查重点顺序：`kpoc_charger` 是否运行 → 容量/动画模式 → Logo 索引 → 解压尺寸 → 绘制矩形/逻辑分辨率/旋转 → 最后才查 DRM/背光/硬件。

## 2. 核心概念：Logo 索引是「代码与资源包之间的 ABI」[已验证]

BootLogo 的打包顺序相当于二进制接口。新增动画帧后，后续数字、百分号和其他动画组的起始索引都会移动。

资源布局示例（wqxga2400）：

| 逻辑内容 | Logo 索引 |
|---|---|
| 100% 完整图 | 41 |
| 动画帧 01–09 | 42–50 |
| 数字 0–9 | 51–60 |
| 百分号 | 61 |

**坑**：资源扩展为 9 帧后，代码仍按旧索引（如 `FAST_CHARGING_NUM_START_0_INDEX=48`）计算 → 数字索引整体错位 → 显示 `627` 等错误数字。

修正示例：

```c
#define FAST_CHARGING_NUM_START_0_INDEX   51
#define FAST_CHARGING_NUM_PERCENT_INDEX   61
#define LOGOS_COUNT_FAST_CHARGING          21
// 动画循环上限 6 帧 → 9 帧: (*charg_anim_low_idx_by_lcm) >= 8
```

**计算规则**：`数字起始索引 = 动画起始索引 + 动画帧数量`；`百分号索引 = 数字起始索引 + 10`；`动画组总数 = 完整图数 + 动画帧数 + 10 + 1`。

## 3. 整图 vs 动态合成（100% vs 1-99%）[已验证]

```c
if (capacity >= 100) {
    // 直接显示一张完整 100% 图片（不依赖数字坐标和索引）
} else {
    // 动画底图 + 十位数字 + 个位数字 + 百分号（多层动态合成）
}
```

**100% 正常 ≠ 1-99% 正常**。两者是完全不同的绘制模型，任何「100% 正常」的结论都不能外推到动态路径。

## 4. 分辨率与旋转 [已验证]

- 面板物理竖屏 `1600x2400`、`ORIENTATION_0`，产品要求横屏显示 → 逻辑宽高应交换：

```c
display_width  = phical_screen.height; // 2400
display_height = phical_screen.width;  // 1600
```

- 不同图层使用独立局部副本，分别旋转：

```c
LCM_SCREEN_T animation_screen = phical_screen;
LCM_SCREEN_T digit_screen = phical_screen;
animation_screen.rotation = 180;   // <100% 动画底图
digit_screen.rotation = 90;        // 动态数字和百分号
// 100% 完整图使用原始 phical_screen
```

- **旋转同时影响像素方向和坐标空间**：只改 rotation 不交换居中计算的宽高，内容方向对但位置错。
- 分辨率参数（如 `{1600, 2400, WQXGA_1600_2400}` + `num_width_fast=52 / num_height_fast=80 / top_margin_fast=760`）必须存在，否则用错误参数产生矩形/位置/解压尺寸异常。

## 5. 排查路径 [已验证]

1. **电量测试矩阵**：7%（单数字）、50%（两位+百分号+底图）、93/99%（高索引）、100%（整图）。只有 100% 正常 → 查动态路径。
2. **确认软件输入一致**：`sha256sum /dev/block/by-name/logo` + build fingerprint；哈希一致只排除 Logo 分区不同，不排除代码索引错。
3. **KPOC 主线日志**：`rg -n -i "kpoc_charger|show_animation|capacity|wireless_charging|get_fast_charging_state"`。
4. **打印资源请求/实际索引**：capacity、帧号、initial/actual logo index、raw_data_size。
5. **核对打包顺序**：从打包规则按顺序列出（完整图→动画帧→数字0-9→百分号→其他）。
6. **核对 BMP 分辨率与解压尺寸**：底图全屏、数字 `52x80`；保留矩形合法性检查。
7. **分层验证旋转**：先底图 → 固定一个数字 → 加第二位+百分号 → 最后测 7/50/99/100%。
8. **无 ADB 时的取证**：KPOC 阶段 adbd 可能不启动，用 MTK DebugLogger / last_kmsg / 串口 / 受 `MTK_LOG_ENABLE` 控制的临时日志。

## 6. 试错记录 [已验证]

- 误判为两台机器硬件差异（实际是电量不同走不同分支——**比较设备前固定电量/充电器/进入方式**）。
- 只校验 Logo 分区哈希（内容一致 ≠ 消费逻辑正确）。
- 把 `get_fast_charging_state: 0` 当最终返回值（日志位置必须结合控制流阅读，打印原始+最终值）。
- 只改尺寸参数（资源索引错位、旋转是独立维度）。
- 照搬 Link8 的全局 `rotation=180` 写法（值传递的局部副本在绘制后赋值，不旋转已绘制的数字）。
- 认为关机阶段一定有 ADB（取决于产品配置，提前准备离线取证手段）。

## 7. 推荐最小诊断日志 [已验证]

```c
SLOGD("capacity=%d mode=%d frame=%d", capacity, draw_anim_mode, frame_index);
SLOGD("display=%dx%d rect=(%d,%d)-(%d,%d)", ...);
SLOGD("animation_rotation=%d digit_rotation=%d", ...);
SLOGD("initial_index=%d actual_index=%d raw_data_size=%d", ...);
```

受编译开关/`MTK_LOG_ENABLE` 控制，避免生产版本高频打印。
