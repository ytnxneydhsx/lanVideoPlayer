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

系统由三个主要物理角色（Clients, Server Side）和两个逻辑平面（Control Plane, Data Plane）组成。

### 2.1 拓扑结构

```mermaid
graph TD
    %% 控制流
    subgraph "Control Plane (Signaling & Mgmt)"
        Core[Core Service]
        TM[Transcoder Manager]
        Core --- TM
    end

    %% 数据流
    subgraph "Data Plane (Media Pipeline)"
        SRS[SRS Media Server]
        FF[FFmpeg Transcoder]
        
        %% Path A: 直通
        Sender_A[Sender (1080p)] == RTMP ==> SRS
        SRS == WebRTC ==> Receiver_A[Receiver (1080p)]
        
        %% Path B: 转码
        Sender_B[Sender (1080p)] == RTMP ==> SRS
        SRS -- RTMP Pull --> FF
        FF -- RTMP Push (360p) --> SRS
        SRS == WebRTC (360p) ==> Receiver_B[Receiver (360p)]
    end
    
    %% 控制关联
    Core -. WS Commands .-> Sender_A
    Core -. WS Commands .-> Sender_B
    Receiver_A -. HTTP API .-> Core
    Receiver_B -. HTTP API .-> Core
    TM -. Process Control .-> FF
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
V1.5 采用 **"断开重连"** 模式，SRS 天然支持多播分发。

**场景描述**: 用户 A 从 1080p 切换到 360p。同时用户 B 正在观看 360p。

1.  **Client 动作**:
    - 用户 A 点击 "360p"。
    - Client 销毁当前 WebRTC 连接 (Connection A)。
    - Client 向 Core 请求 `/api/play?q=360p`。

2.  **Core 响应**:
    - 发现 `cam01_360p` 转码任务已存在（因为用户 B 在看）。
    - 直接返回 URL: `webrtc://.../live/cam01_360p`。

3.  **SRS 内部机制 (Fan-out)**:
    - 用户 A 使用新 URL 发起 WHIP/WebRTC 连接。
    - SRS 接受连接，将现有的 `live/cam01_360p` 数据流**复制一份**发给用户 A。
    - **结果**: 用户 A 和用户 B 同时订阅了同一个 360p 流，SRS 的内存中只有一份 360p 的输入，但分发了两路输出。

---

## 4. 媒体管道详设 (Media Pipeline)

### 4.1 SRS 部署与配置 (Configuration)
SRS 作为纯粹的数据交换中心，需开启 RTMP 推流端口 (1935) 和 WebRTC 播放端口 (8000/UDP)。

**srs.conf 核心配置片段**:
```nginx
listen              1935;
max_connections     1000;
daemon              off;
srs_log_tank        console;

http_api {
    enabled         on;
    listen          1985;
}

rtc_server {
    enabled         on;
    listen          8000;
    candidate       $CANDIDATE; # 自动获取本机 IP
}

vhost __defaultVhost__ {
    rtc {
        enabled     on;
        rtmp_to_rtc on;    # 关键：开启 RTMP -> WebRTC 协议转换
        rtc_to_rtmp off;
    }
    http_remux {
        enabled     off;   # 本项目不使用 HTTP-FLV/HLS
    }
}
```

### 4.2 流地址命名规范 (URL Schema)
系统严格遵守以下命名约定，以区分“原始流”和“转码流”。

**基本格式**: `rtmp://{server_ip}/live/{stream_key}`

| 流类型 | Stream Key 规则 | 示例 (Sender ID=cam01) | 说明 |
| :--- | :--- | :--- | :--- |
| **原始流 (Source)** | `{sender_id}` | `cam01` | Sender 推送的唯一地址 |
| **转码流 (360p)** | `{sender_id}_360p` | `cam01_360p` | FFmpeg 产出的低清流 |
| **转码流 (720p)** | `{sender_id}_720p` | `cam01_720p` | FFmpeg 产出的高清流 |

### 4.3 管道建立过程 (Channel Establishment)

**场景：直通模式 (Source Pass-through)**
1.  **Sender**: 推送 `rtmp://.../live/cam01`。
2.  **SRS**: 接收 RTMP 包，建立 `live/cam01` 频道。自动将其转封装为 WebRTC 格式。
3.  **Receiver**: 请求播放 `webrtc://.../live/cam01`。
4.  **SRS**: 将内存中的音视频包发送给 Receiver。

**场景：转码模式 (Transcoding Mode)**
1.  **Sender**: 推送 `rtmp://.../live/cam01`。
2.  **Core (FFmpeg)**:
    - **Pull**: 从 SRS 拉取 `rtmp://.../live/cam01`。
    - **Process**: 解码 -> 缩放 -> 编码。
    - **Push**: 推送回 SRS `rtmp://.../live/cam01_360p`。
3.  **SRS**: 此时内存中存在两个独立的频道：`cam01` 和 `cam01_360p`。
4.  **Receiver**: 请求播放 `webrtc://.../live/cam01_360p`。

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
