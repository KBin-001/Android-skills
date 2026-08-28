# 日志分析（kernel imgsensor / Camera HAL）

> 分层：通用排障规则 + MTK 平台关键词

## 1. 日志采集 [已验证]

```bash
# Kernel 侧
adb root
adb shell dmesg | grep -i "<sensor>"
adb shell dmesg | grep -Ei "imgsensor|camera|sensor|i2c|regulator|mclk|cam_pwr"

# HAL 侧
adb logcat | grep -Ei "camera|mtkcam|<sensor>"
```

## 2. 找“第一有效异常” [已验证]

不要被最后的结果日志带偏。优先搜索第一次出现 fallback / 拒绝 / 失败的位置。

- 尺寸问题：`odd|unsupported|replace|HEIC size|requestSize|targetSize|updatePictureSize|updatePictureInfo|configureStreams`
- 连接问题：`ERROR_SENSOR_CONNECT_FAIL|sensor connect fail|I2C read sensor ID fail|sensor id`
- HAL 问题：`metadata load fail|tuning module missing|ISP module missing|IdxMgr|ISP_mapping|ISP_param|Camera open fail|configureStreams`

**有效信号 vs 噪声**：如 HEIF 案例中，`ignore odd HEIC size` 是第一现场；后续 HAL `configureStreams 1080x720`、Encoder 尺寸都只是执行结果（结果噪声）。无关系统的报错（Bluetooth VINTF、LBS service 等）要主动忽略。

## 3. 分层定位 [已验证]

根据日志内容判断问题层：

| 日志证据 | 问题层 |
|---|---|
| 无 probe / ID 读不到 / I2C fail | 硬件 / Kernel 驱动 / DTS |
| probe OK 但 open fail | SensorList / Metadata / Tuning / Soong |
| open OK 但出图异常 | tuning / dataformat / 帧率 |
| 能力/尺寸错误 | metadata 声明 |
| 切换/流程异常 | HAL stream 配置 / App |

## 4. 开机验证命令集 [已验证]

```bash
adb shell dmesg | grep -Ei "imgsensor|<sensor>|i2c|regulator|mclk"
adb shell cat /proc/modules | grep imgsensor
adb shell cat /sys/kernel/debug/regulator/regulator_summary | grep -i vmc
adb shell cat /proc/mtk_gpio/soc.pinctrl | grep -E "^071:|^072:|^075:"
```

检查顺序：KO 加载 → sensor power on → MCLK/RST/电压 → I2C ACK 与 ID → HAL 枚举 MAIN/SUB/MAIN2 → 分辨率/方向/颜色/曝光/对焦。

## 5. property 与日志结合判断 [已验证]

HEIF 案例教训：`getprop vendor.mtk.camera.app.heif.flow` 等返回空，不代表功能关闭——代码可能走默认值。必须结合源码默认值与运行日志（如 `HEIF_AOSP_FLOW supportedFormats`）判断，不能只凭空属性下结论。

## 6. 排除法经验 [已验证]

- 不要只看产品名 custom 目录：相机能力通常按 `platform + sensor` 组织（如 `custom/mt8189/hal/imgsensor_metadata/s5k3m5sx_mipi_raw/`）。
- 修改能力后注意 App 缓存：metadata 更新后旧值仍可能被读取，刷机后 `pm clear com.mediatek.camera`。
