# Sender Client 开发实施指南

> **模块路径**: `/sender`
> **核心职责**: 视频采集、H.264 编码、RTMP 推流、远程指令执行。

## 1. 模块架构 (Internal Architecture)

Sender 采用 **异步 IO (asyncio)** 驱动的主循环，内部管理着一个 FFmpeg 进程池。

```mermaid
graph TD
    subgraph "Sender Process"
        Main[Main Loop (Asyncio)]
        WS[WebSocket Client]
        Disc[UDP Discovery]
        Pool[FFmpeg Process Pool]
        
        Disc -->|1. Found IP| WS
        WS -->|2. Connect| Main
        Main -->|3. Cmd Start| Pool
        Pool -->|4. Popen| OS[OS Processes]
    end
```

## 2. 关键类设计 (Class Design)

### 2.1 `DiscoveryService` (`pipeline/discovery.py`)
- **功能**: 循环发送 UDP 广播，直到收到 Core 响应。
- **重试策略**: 指数退避 (1s, 2s, 4s, 8s...)，最大 30s。

### 2.2 `SignalingClient` (`pipeline/signaling.py`)
- **功能**: 维护与 Core 的 WebSocket 长连接。
- **心跳**: 每 5s 发送 `{"type": "ping"}`。
- **断线重连**: 必须实现自动重连逻辑，重连期间**不停止**正在运行的推流任务（保持画面不断）。

### 2.3 `StreamManager` (`pipeline/stream_mgr.py`)
- **数据结构**: `active_streams: Dict[str, subprocess.Popen]`
- **方法**:
  - `start_stream(source_id, rtmp_url, config)`: 启动 FFmpeg。
  - `stop_stream(source_id)`: 发送 SIGTERM，等待 5s，若不退则 SIGKILL。
  - `get_status()`: 返回所有流的健康状态。

---

## 3. FFmpeg 极低延迟参数调优 (The Secret Sauce)

这是本项目的核心竞争力。请严格按照以下参数配置 `ffmpeg_wrapper.py`。

### 3.1 基础命令模板
```python
cmd = [
    "ffmpeg",
    "-f", input_format,       # Windows: dshow, Linux: v4l2, Mac: avfoundation
    "-i", device_name,
    "-c:v", "libx264",
    "-preset", "ultrafast",   # 关键：最快编码速度
    "-tune", "zerolatency",   # 关键：关闭帧缓存，即时输出
    "-pix_fmt", "yuv420p",    # 兼容性最好
    "-g", "60",               # GOP=60 (2秒一个关键帧)，平衡延迟与画质
    "-b:v", bitrate,          # e.g., "2000k"
    "-s", resolution,         # e.g., "1280x720"
    "-f", "flv",
    rtmp_url
]
```

### 3.2 平台差异化 (Platform Specifics)

| 平台 | Input Format | Device Name 示例 | 备注 |
| :--- | :--- | :--- | :--- |
| **Windows** | `dshow` | `video="Integrated Camera"` | 需先运行 `ffmpeg -list_devices true -f dshow -i dummy` 获取名称 |
| **Linux (RPi)** | `v4l2` | `/dev/video0` | 树莓派可尝试硬件编码 `-c:v h264_omx` |
| **macOS** | `avfoundation` | `"0"` | 需授予终端摄像头权限 |

---

## 4. 业务逻辑状态机 (FSM)

Sender 的每个 Source 都有独立的状态流转：

- **IDLE**: 初始状态，无 FFmpeg 运行。
- **STARTING**: 收到 `cmd_start`，正在启动 FFmpeg。
- **STREAMING**: FFmpeg 运行中，且 `poll()` 返回 None。
- **ERROR**: FFmpeg 意外退出（exit code != 0）。自动重试 3 次后放弃。

## 5. 详细业务逻辑流 (Detailed Business Logic)

### 5.1 启动全流程 (Startup Sequence)

1.  **硬件自检**: 
    - 运行 `ffmpeg -list_devices` 枚举本机所有摄像头。
    - 生成 `sources_list` (e.g., `[{id: "cam0", name: "Integrated"}, {id: "cam1", name: "USB"}]`)。
2.  **寻找组织 (Discovery)**:
    - 启动 UDP Listener 监听 9999 端口。
    - 每 2 秒发送广播包 `{"magic": "lan_video_discovery_v1"}`。
    - **Blocking**: 直到收到 Core 回复 `{"ip": "192.168.1.100"}`。
3.  **建立信令 (Signaling)**:
    - 连接 `ws://192.168.1.100:8000/ws/sender/{my_mac_addr}`。
    - 发送 `register` 包，附带 `sources_list`。
    - 启动心跳协程 `heartbeat_loop`。

### 5.2 动态推流控制 (Dynamic Streaming)

当收到 `cmd_start` 消息时：
1.  **参数提取**: 获取 `source_id`, `rtmp_url`, `resolution`。
2.  **冲突检查**: 
    - 检查 `active_streams` 中是否已有该 `source_id` 的任务？
    - 如果有，先执行 `stop_stream` 强制停止旧任务（重置）。
3.  **启动进程**:
    - 组装 FFmpeg 命令。
    - `subprocess.Popen(cmd, stdout=PIPE, stderr=PIPE)`。
    - 将 `PID` 存入 `active_streams[source_id]`。
4.  **状态反馈**: 向 Core 发送 `{"type": "status_update", "source_id": "...", "state": "streaming"}`。

### 5.3 异常恢复与保活 (Resilience)

**场景 A: FFmpeg 意外挂掉 (Crash)**
- 守护协程 `watchdog_loop` 每 1 秒轮询所有 `active_streams`。
- 如果发现某进程 `poll() is not None` (已退出) 且 `returncode != 0`:
    - 记录日志 `[ERROR] FFmpeg crashed!`.
    - **自动重启**: 立即尝试重新 `Popen`（最多重试 3 次）。
    - 超过 3 次失败，向 Core 发送 `{"type": "error", "msg": "Camera device failure"}`。

**场景 B: Core 服务断开 (Network Split)**
- WebSocket 抛出 `ConnectionClosed` 异常。
- **保持推流**: 不要停止 FFmpeg！(也许网络只是抖动，SRS 还是通的)。
- **静默重连**: 进入 `reconnect_loop`，指数退避尝试重连 Core。
- 重连成功后，重新发送 `register`，并上报当前正在推流的状态（Core 可能重启过，需要同步状态）。

---

## 6. 开发任务清单 (Todo List)

### Phase 1: 基础联通
- [ ] 实现 `DiscoveryService`: 能打印出 Core IP。
- [ ] 实现 `SignalingClient`: 能连上 WS 并发送 `register`。
- [ ] 编写 `hardware/camera.py`: 跨平台列出摄像头列表。

### Phase 2: 推流引擎
- [ ] 实现 `FFmpegWrapper`: 封装 `subprocess.Popen`，支持日志重定向到 `logs/`。
- [ ] 调试 Windows/Linux 下的 FFmpeg 参数，确保延迟 < 500ms。

### Phase 3: 健壮性
- [ ] 实现看门狗：当 FFmpeg 崩溃时自动重启。
- [ ] 实现 TUI 界面 (使用 `Textual` 库)：显示实时码率和 CPU 占用。
