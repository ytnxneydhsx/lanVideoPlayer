# LanVideoPlayer V1.5 完整技术规格书 (Full Spec)

> **版本**: 1.5.0
> **状态**: Draft
> **核心特性**: 自动发现 · 按需推流 · 动态转码 · 中央控制

---

## 1. 系统概述

LanVideoPlayer 是一个高内聚、低耦合的局域网视频传输系统。V1.5 版本在实现“零配置即插即用”的基础上，引入了服务器端动态转码与中央控制机制，以适应复杂的网络环境和多样的客户端需求。

### 1.1 核心能力矩阵

| 能力 | 描述 | 所属阶段 |
| :--- | :--- | :--- |
| **自动发现** | Sender 自动寻找 Core，无需手动配置 IP | V1.0 |
| **按需推流** | 无人观看时 Sender 休眠，有人观看时毫秒级唤醒 | V1.0 |
| **中央控制** | Core 可强制设定 Sender 的推流分辨率与码率 | V1.5 (Enhanced) |
| **自适应画质** | Receiver 可请求 360p/720p，服务器自动转码 | V1.5 |

---

## 2. 总体架构图 (The Big Picture)

系统由控制平面 (Control Plane) 和数据平面 (Data Plane) 组成。

```mermaid
graph TD
    %% 角色定义
    subgraph "Clients"
        S[Sender (采集端)]
        R[Receiver (播放端)]
    end

    subgraph "Server Side"
        subgraph "Core Service (Brain)"
            Disc[UDP Discovery]
            Sig[WebSocket Signaling]
            TM[Transcoder Manager]
        end
        
        subgraph "Media Infrastructure"
            SRS[SRS 5.0]
            FF[FFmpeg Transcoder]
        end
    end

    %% 连接关系
    S -. 1. UDP Broadcast .-> Disc
    S <== 2. WS Connect ==> Sig
    
    R -- 3. POST /play?q=360p --> Sig
    Sig -- 4. Spawn --> FF
    
    S -- 5. RTMP Push (Source) --> SRS
    FF -- 6. Pull & Transcode --> SRS
    SRS -- 7. WebRTC Play --> R
```

---

## 3. 核心业务流程

### 3.1 启动与握手 (Bootstrapping)
Sender 启动后，必须完成以下步骤才能进入就绪状态：
1.  **UDP 发现**: 发送广播，获取 Core IP。
2.  **能力上报**: 建立 WebSocket，发送 `register` 消息，携带 `max_resolution` (e.g., 1080p)。
3.  **配置下发 (V1.5)**: Core 根据策略下发 `init_config`，例如强制限制为 720p。
4.  **待机**: Sender 进入 `IDLE` 状态，保持心跳，不推流。

### 3.2 播放与协商 (Play Negotiation)
当用户在 Receiver 请求播放时：
1.  **请求**: `POST /api/play/{id}`，Body: `{"quality": "360p"}`。
2.  **校验**:
    *   若 `request_q > source_q`: **拒绝 (HTTP 400)**。
    *   若 `request_q == source_q`: **直通 (Pass-through)**，返回源流地址。
    *   若 `request_q < source_q`: **转码 (Transcoding)**。
3.  **转码调度**:
    *   Core 检查是否已有对应的 FFmpeg 进程。
    *   若无，启动 `ffmpeg -i source -s 360p ...`。
    *   等待进程稳定 (Ready)。
4.  **响应**: 返回播放地址 `webrtc://.../stream_360p`。

### 3.3 切换分辨率 (Quality Switch)
V1.5 采用 **"断开重连"** 模式：
1.  用户点击 UI 切换画质。
2.  Receiver 销毁当前 WebRTC 连接。
3.  Receiver 重新请求 API 获取新画质地址。
4.  建立新连接。
    *   *注: 期间会有 <1s 的黑屏加载。*

---

## 4. 模块详细规格

### 4.1 Core Service (Python)
- **API**: FastAPI
- **Transcoder Manager**: 负责管理 FFmpeg 子进程，具备“看门狗”功能，30s 无人观看自动杀进程。
- **配置**: `config.yaml` 定义默认策略（如：默认是否允许转码，最大并发转码数）。

### 4.2 Sender (Python TUI)
- **FFmpeg 封装**: 使用 `subprocess` 调用，参数必须包含 `-tune zerolatency`。
- **指令响应**: 需处理 `cmd_start`, `cmd_stop`, `cmd_reconfigure` 指令。

### 4.3 Receiver (Electron)
- **UI**: 增加清晰度选择下拉框 `[Source, 720p, 360p]`。
- **逻辑**: 播放前先调用 `/api/streams` 获取 Sender 的 `source_resolution`，以此动态生成下拉选项（不显示高于源的选项）。

### 4.4 SRS (Media Server)
- **配置**: 开启 WebRTC, RTMP, HTTP-API。
- **职责**: 纯粹的流转发与分发，不处理业务逻辑。

---

## 5. 数据结构参考

### 5.1 Sender -> Core (Register)
```json
{
  "type": "register",
  "device_id": "cam_01",
  "capabilities": {
    "max_resolution": "1920x1080",
    "supported_framerates": [30, 60]
  }
}
```

### 5.2 Core -> Sender (Start Command)
```json
{
  "type": "cmd_start",
  "params": {
    "rtmp_url": "rtmp://192.168.1.100/live/cam_01",
    "resolution": "1280x720",
    "bitrate": "2000k"
  }
}
```

---

## 6. 开发路线图 (Roadmap)

1.  **M1 (信令联通)**: 跑通 UDP 发现与 WebSocket 注册。
2.  **M2 (基础推流)**: 实现 V1.0 的按需推流（直通模式）。
3.  **M3 (接收端 MVP)**: Electron 播放器跑通。
4.  **M4 (转码引擎)**: V1.5 核心，实现 Transcoder Manager 与转码逻辑。
