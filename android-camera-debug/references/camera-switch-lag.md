# 摄像头切换卡顿 / open / preview / recording 异常

> 分层：通用排障规则为主；本项目知识库尚无“切换卡顿”的直接闭环案例，相关结论标注 [待验证]，仅作为检查框架，使用前需在目标平台确认。

## 1. Camera open / preview / recording 异常分层 [已验证部分]

按“哪一层先报错”定位：

| 现象 | 优先检查 |
|---|---|
| open 直接失败 | SensorList（Kernel+HAL 两处）、Metadata/Tuning 是否齐全、Soong 是否注册 |
| open 慢/超时 | power sequence delay 是否过长、I2C 是否反复 retry、ID 读取是否失败后重试 |
| preview 黑屏但无报错 | streaming 是否开启、sensor_output_dataformat、帧率（pclk/line_length/frame_length）、ISP tuning |
| preview 花屏/条纹 | MIPI lane 配置、bit order、CSI port、clock 频率 |
| recording 失败/卡顿 | codec 能力、分辨率对齐（参考 metadata-tuning.md）、stream 配置 |
| 拍照尺寸不对 | 按 metadata-tuning.md 的尺寸检查表逐层比对 |

## 2. 摄像头切换卡顿（前↔后）[待验证]

> 本项目暂无直接闭环记录。以下为通用 MTK 排查框架，按可验证性排序：

1. **确认“卡顿”定义**：是切换耗时久、黑屏时间长，还是切换后预览卡顿？两者方向不同。
2. **切换耗时久**：检查
   - 前后摄是否共用电源 GPIO/regulator（本项目 cam0/cam1 共用 GPIO71/72/75 → 切换时不能简单关断共享 rail）[已验证共享事实，卡顿关联待验证]
   - power down → power up 序列 delay
   - HAL 是否做了 sensor 预取/预热（`sensor_mgr` 相关），未预取时切换需要完整 re-open
3. **切换后预览卡顿**：检查 frame rate 设置、stream 配置是否一致、ISP/tuning 是否加载完整。

**建议排查动作**（待验证项先做观察，不要直接改）：

```bash
# 抓切换过程的时序
adb logcat -c && 触发前后摄切换 && adb logcat -d -v threadtime | grep -Ei "mtkcam|switch|open|close|configureStreams|sensor"
adb shell dmesg | tail -200 | grep -Ei "imgsensor|power"
```

## 3. 共享电源注意事项 [已验证]

本项目 cam0（GC08A8）与 cam1（HI1333）共用 AVDD GPIO71、DOVDD GPIO72（DVDD 不同：cam0=75、cam1=76）。修改上下电逻辑时必须考虑共享电源，避免一个 slot 的电源操作影响另一个。

## 4. suspend/resume 检查项 [已验证部分]

- 多次打开/关闭 Camera 后是否正常（重复 open/close 泄漏）。
- suspend/resume 后 Camera 是否恢复：检查 streaming off/on、power down/up 是否成对。
- [待验证] 若 resume 后黑屏，优先检查 power sequence 是否在 resume 路径被完整重放。
