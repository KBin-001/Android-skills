# TP / EMR 联动（触摸屏与电磁笔互斥）

> 分层：MTK/驱动规则；核心案例 Himax TP + Huion EMR [已验证]

## 1. 问题场景 [已验证]

手写笔（EMR）与手指触摸（TP）同时操作时的干扰：笔靠近时手指触摸仍在上报，导致误触/跳笔。

## 2. 互斥设计模式 [已验证]

**控制端（EMR 驱动，如 Huion tablet）**：检测笔状态并通知 TP 驱动。
**接收端（TP 驱动，如 Himax）**：根据笔状态决定是否拦截触摸上报。

### 通信桥梁（TP 驱动导出符号）

```c
unsigned int himax_pen_state = 0;  // 0: PEN_NOT_BUSY, 1: PEN_BUSY
EXPORT_SYMBOL_GPL(himax_pen_state);

void himax_force_touch_up(void)    // 笔靠近时强制所有手指抬起
{
    struct himax_ts_data *ts = hx_s_ts;
    if (!ts || !g_tp_status) return;
    if (gtp_report_status) {
        himax_report_all_leave_event(ts);
        gtp_report_status = 0;
    }
}
EXPORT_SYMBOL_GPL(himax_force_touch_up);
```

### 笔状态监测（EMR 驱动工作队列）

```c
// 在 huion_ts_work_func 中添加状态机
if (state & 0x10) cur_pen_status = 1; else cur_pen_status = 0;

if (cur_pen_status == 0 && pre_pen_status == 1) {
    himax_pen_state = PEN_NOT_BUSY;   // 笔离开，释放互斥
} else if (cur_pen_status == 1) {
    himax_pen_state = PEN_BUSY;
    if (pre_pen_status == 0)          // 刚进入
        himax_force_touch_up();       // 立即掐断当前触摸
}
pre_pen_status = cur_pen_status;
```

### 触摸上报拦截（TP 驱动数据入口）

```c
// himax_report_data 入口
if (get_pen_state() == PEN_BUSY) {
    return ts_status;   // 直接返回，不执行 input_report
}
```

**关键点**：笔忙时 TP 驱动依然运行和读取数据，但坐标永远不会提交给 Android 系统。

## 3. 通用模式 [已验证/待验证]

- 互斥三要素：**状态共享**（导出符号/全局变量）→ **状态监测**（EMR 侧状态机）→ **上报拦截**（TP 侧入口拦截）。
- 边界处理：笔刚进入时强制 touch up（清空旧状态）；笔离开时释放互斥。
- 涉及两个驱动时用 `EXPORT_SYMBOL_GPL` + 外部声明，避免耦合进各自模块。

## 4. 验证 [已验证]

- 笔悬停/书写时手指触摸不响应。
- 笔离开后手指触摸立即恢复。
- 笔从「按下手指」状态靠近时，手指事件被正确掐断（无残留触摸）。
