# Metadata / Tuning / 分辨率 / wininfo / 尺寸对齐

> 分层：MTK 平台规则 + 通用排障规则；`[已验证]` 来自项目复盘

## 1. 四套 Sensor 参数目录 [已验证]

| 目录 | 内容 | 缺了会怎样 |
|---|---|---|
| `custom/common/hal/imgsensor_metadata/sensor/<sensor>/` | Sensor 通用静态能力：active/pixel array、Bayer、black/white level、ISO/曝光范围、方向、物理尺寸 | Camera open fail / metadata load fail |
| `custom/common/legacy/hal/imgsensor_metadata/sensor/<sensor>/` | 给 MTK legacy metadata provider 使用。**Android 17 + Kernel 6.12 不代表 legacy 已移除**，两套都要补 | 一条 HAL 路径读到旧参数 |
| `custom/<plat>/hal/imgsensor/ver1/<sensor>/` | 平台 ISP tuning：AE/AWB/AF、CCM/COLOR/GGM/OBC/BPC、Preview/Video/Capture/HDR/夜景 | 能出图但偏色、过曝、噪点大 |
| `custom/<plat>/hal/imgsensor_metadata/<sensor>/` | 平台/项目级：lens/module/project 静态 metadata、request metadata、availableKeys | 只有 1M 没有 13M、无法对焦、App 能力错误 |

> 分辨率、Bayer、ISO 等关键能力修改时，**两边 metadata 都检查**（common 与 legacy），避免一条 HAL 路径读到旧参数。

## 2. sensor_output_dataformat [已验证]

驱动中的 `sensor_output_dataformat` 必须符合实际 Bayer 顺序。RAW Bayer 顺序或 tuning 来源不匹配 → 画面偏红/偏紫。合入新 sensor 时重点确认 `sensor_output_dataformat`、preview/capture 分辨率、PCLK、line length、frame length。

## 3. 尺寸一致性检查（HEIF 案例通用化）[已验证]

**现象**：JPEG 拍 13M 正常，HEIF 拍 13M 实际只有 ~0.8M（如 `720×1080`）。

**第一有效异常**（App 日志）：

```text
[getBestHeicOutputSize] ignore odd HEIC size = 4415x2943
[getBestHeicOutputSize] replace unsupported HEIC size 4415x2943 with 1080x720
```

**根因**：Sensor metadata 在 BLOB 和 YCbCr_420_888 里声明了奇数尺寸 `4415×2943`。YUV420 要求偶数采样，平台 C2 HEIF Encoder 还要求 16×16 对齐 → App 拒绝该尺寸并回退到同比例（3:2）的 `1080×720`。

**修复**：把 `config_static_metadata_project.h` 中 BLOB 与 YUV 两组尺寸同步改为满足 16 对齐的 `4416×2944`。**不要删除 App 的奇数尺寸保护**（保护暴露的是上游声明错误，应修 metadata），不要只改 BLOB 或只改 YUV。

**通用排查（尺寸不一致检查表）**：

- [ ] 确认问题格式：JPEG / HEIF / RAW
- [ ] 记录 UI 选择的精确分辨率（不是“几 M”）
- [ ] 搜 `updatePictureSize`（App 保存值）
- [ ] 比较 `requestSize` 与 `targetSize`
- [ ] 搜 `updatePictureInfo`（Surface 尺寸）
- [ ] 搜 `configureStreams`（HAL 收到尺寸）
- [ ] 搜 `CCodecConfig raw.size`（编码尺寸）
- [ ] 检查最终文件主图/旋转/thumbnail
- [ ] 反查 `imgsensor_metadata/<sensor>/` 的 BLOB/YUV/RAW/HEIC 声明
- [ ] 检查宽高奇偶、2/16/32 对齐、Codec max size
- [ ] 同步修改相关 pixel format
- [ ] 刷机后 `pm clear com.mediatek.camera` 清旧设置再验证

**判断分支**：

| 观察 | 检查方向 |
|---|---|
| 设置值本身错误 | UI、DataStore、默认值、restriction |
| request 对但 target 改变 | App capability/filter/fallback |
| App target 对但 HAL stream 改变 | Framework/HAL negotiation |
| HAL 对但 Encoder 改变 | MediaCodec/C2/OMX |
| 编码对但图库显示错 | HEIF container、primary image、thumbnail、rotation |
| 只在特定 sensor 发生 | 对应 `imgsensor_metadata/<sensor>` |

**核心经验**：优先找第一次改变尺寸/第一次 fallback 的位置；“JPEG 能拍”不能证明相同尺寸可用于 HEIF；能力声明必须跨层一致（Sensor 可输出 ∩ HAL 声明 ∩ App 会选择 ∩ format/stride 合法 ∩ Codec 支持）。

## 4. wininfo / preview size [待验证]

- 本项目经验集中在 metadata 尺寸声明与对齐。wininfo（active window / crop window 信息）在 MTK 中通常位于 sensor 驱动的 `get_info`/win info 结构与 metadata 中。
- [待验证] 若出现“预览比例不对/裁切异常/画幅与设置不符”，优先核对 sensor 驱动 win 信息与 metadata active array 是否一致，再检查 App 侧 preview ratio 匹配逻辑。

## 5. Camera HAL log 关键词 [已验证]

```text
Camera open fail | metadata load fail | tuning module missing | ISP module missing
preview abnormal | configureStreams | IdxMgr | ISP_mapping | ISP_param | camera provider
```

**Kernel probe 成功 ≠ Camera HAL 正常。** Metadata/Tuning 缺失时的典型现象：Camera open fail、颜色/曝光/AE/AWB 异常、preview 异常。
