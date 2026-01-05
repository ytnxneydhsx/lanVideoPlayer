# 组件方案二：发送端客户端 (Sender Client)

## 1. 组件定位
发送端是运行在采集设备（如树莓派、工控机、笔记本）上的“无头”或“极简UI”程序。它负责视频采集和推流。

## 2. 技术架构
- **语言**: Python 3.10+
- **界面**: TUI (Text User Interface) - 使用 `Rich` 或 `Textual` 库，资源占用极低。
- **核心引擎**: FFmpeg (通过 `subprocess` 调用)。
- **通信**: `websockets` (Client), `socket` (UDP)。

## 3. 详细设计

### 3.1 启动流程 (Bootstrapping)
1.  **设备枚举**: 启动时运行 `ffmpeg -list_devices` 解析本机可用摄像头。
2.  **服务发现**:
    - 进入 `DiscoveryLoop`。
    - 发送 UDP 广播。
    - 等待 Core 回复。
    - 失败则指数退避重试 (3s, 5s, 10s...)。
3.  **连接建立**: 连上 WebSocket，发送 `register` 包，上报设备列表和默认分辨率配置。

### 3.2 视频推流引擎 (Stream Engine)
不直接使用 OpenCV (性能差)，而是封装 FFmpeg 进程。

**关键配置 (Low Latency)**:
- **编码器**: `libx264`
- **预设**: `-preset ultrafast` (牺牲压缩率换取速度)
- **调优**: `-tune zerolatency` (关闭帧缓存)
- **GOP**: `-g 60` (假设 30fps，2秒一个关键帧)
- **协议**: RTMP (推流最稳)

**Python 实现伪代码**:
```python
def start_ffmpeg(self, rtmp_url, res):
    cmd = [
        "ffmpeg", "-f", "avfoundation", "-i", "0",
        "-c:v", "libx264", "-preset", "ultrafast", "-tune", "zerolatency",
        "-s", res, "-f", "flv", rtmp_url
    ]
    self.process = subprocess.Popen(cmd, stdout=subprocess.DEVNULL)
```

### 3.3 TUI 界面设计
虽然是 TUI，但应提供必要的可视化信息：
- **Header**: 显示连接状态 (Online/Offline)，当前核心服务 IP。
- **Body**:
  - 当前状态: [IDLE] / [STREAMING]
  - 推流时长: 00:12:34
  - 实时日志窗口: 显示 FFmpeg 输出或 WebSocket 消息。
- **Footer**: 快捷键提示 (Q: Quit, R: Restart Discovery)。

### 3.4 异常处理 (Watchdog)
- **网络断开**: 自动重连 WebSocket，重连期间停止推流。
- **FFmpeg 崩溃**: 监控子进程 `poll()` 返回值，若异常退出立即报警并尝试重启。

## 4. 依赖管理
需要确保宿主机安装了 FFmpeg 4.0+。
```txt
rich>=10.0.0
websockets>=10.0
psutil>=5.8.0
```
