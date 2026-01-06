# V1.5 系统拓扑与接口规范 (Topology & API Spec)

## 1. 系统物理拓扑图 (Physical Topology)

本图展示了各个组件在网络中的位置及其交互协议。系统原生支持 **N 个 Sender** 和 **M 个 Receiver** 的任意并发组合。

```mermaid
graph TD
    %% 节点样式定义
    classDef client fill:#e1f5fe,stroke:#01579b,stroke-width:2px;
    classDef server fill:#fff3e0,stroke:#e65100,stroke-width:2px;
    classDef media fill:#f3e5f5,stroke:#4a148c,stroke-width:2px;

    %% 客户端层 (Client Layer)
    subgraph "Clients (N:M Concurrency)"
        S1[Sender 1]:::client
        Sn[Sender ... N]:::client
        R1[Receiver 1]:::client
        Rm[Receiver ... M]:::client
    end

    %% 服务端层 (Server Layer)
    subgraph "Server Infrastructure"
        Core[Core Service]:::server
        SRS[SRS Media Server]:::media
        FF[FFmpeg Worker Pool]:::media
    end

    %% 通信链路 (Links)
    %% 1. 发现
    S1 -.->|"1. UDP Broadcast"| Core
    Sn -.->|"1. UDP Broadcast"| Core
    
    %% 2. 信令
    S1 <==>|"2. WebSocket"| Core
    Sn <==>|"2. WebSocket"| Core
    R1 <-->|"3. HTTP REST"| Core
    Rm <-->|"3. HTTP REST"| Core
    
    %% 3. 控制
    Core -->|"4. Process Spawn (1:1 per stream)"| FF
    SRS -.->|"5. HTTP Callback"| Core
    
    %% 4. 媒体流 (Media Plane)
    S1 ==>|"6. RTMP Publish"| SRS
    Sn ==>|"6. RTMP Publish"| SRS
    FF ==>|"7. RTMP Pull/Push (Loopback)"| SRS
    SRS ==>|"8. WebRTC Play (Fan-out)"| R1
    SRS ==>|"8. WebRTC Play (Fan-out)"| Rm
```

#### 图例说明 (Legend)

| 视觉元素 | 含义 | 协议示例 |
| :--- | :--- | :--- |
| **矩形颜色** | 🟦 客户端 (Client) <br> 🟧 业务服务 (Control Plane) <br> 🟪 媒体设施 (Data Plane) | - |
| **多节点 (S1, Sn)** | **水平扩展** <br> 支持任意数量的设备并发接入。 | Sender 1...N |
| **粗实线 (`==>`)** | **高带宽/重数据流** <br> 传输视频/音频数据包。 | RTMP, WebRTC |
| **细实线 (`-->`)** | **控制指令/短连接** <br> 单向命令或 HTTP 请求。 | Process Spawn, REST API |
| **双线 (`<==>`)** | **长连接** <br> 保持在线的双向信令通道。 | WebSocket |
| **虚线 (`-.->`)** | **异步/事件** <br> 广播消息或回调通知。 | UDP Broadcast, Webhook |

---

## 2. 通信协议矩阵 (Communication Matrix)

| 链路 | 源组件 | 目标组件 | 协议/端口 | 频率 | 数据类型 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **发现** | Sender | Core | UDP / 9999 | 启动时一次 | JSON Magic Packet |
| **信令** | Sender | Core | WS / 8000 | 长连接 | 状态同步, 控制指令 |
| **业务** | Receiver | Core | HTTP / 8000 | 按需 | JSON API |
| **推流** | Sender | SRS | RTMP / 1935 | 持续 | H.264 Video |
| **转码** | FFmpeg | SRS | RTMP / 1935 | 持续 | H.264 Video |
| **拉流** | Receiver | SRS | WebRTC / 8000(UDP) | 持续 | RTP Media Packets |
| **回调** | SRS | Core | HTTP / 8000 | 事件触发 | JSON Hook |

---

## 3. 接口定义 (API Specification)

### 3.1 HTTP REST API (面向 Receiver/Admin)

#### `GET /api/streams`
获取当前在线设备及其所有视频源的状态。

**Response 200 OK**:
```json
[
  {
    "device_id": "raspi_01",
    "sources": [
      {
         "id": "cam_front",
         "status": "streaming",
         "available_qualities": ["source", "360p"]
      },
      {
         "id": "screen_share",
         "status": "idle"
      }
    ]
  }
]
```

#### `POST /api/play/{device_id}/{source_id}`
请求播放地址（被动触发）。

**Request Body**:
```json
{
  "quality": "360p" // 可选: source (default), 720p, 360p
}
```

**Response 200 OK**:
```json
{
  "url": "webrtc://192.168.1.100/live/raspi_01_cam_front_360p",
  "mode": "transcoding"
}
```

#### `POST /api/admin/control` (New in V1.5)
管理员强制控制接口（主动触发）。可用于实时开关特定视频源。

**Request Body**:
```json
{
  "device_id": "raspi_01",
  "source_id": "cam_front",
  "action": "start", // or "stop"
  "params": {       // Optional for start
    "resolution": "720p"
  }
}
```

**Response 200 OK**:
```json
{ "success": true, "message": "Command sent to sender" }
```

---

### 3.2 WebSocket 信令 (面向 Sender)

**Endpoint**: `/ws/sender/{device_id}`

#### 消息类型: `register` (Sender -> Core)
连接建立后立即发送。上报该设备拥有的所有视频源。
```json
{
  "type": "register",
  "capabilities": {
    "sources": [
       { "id": "cam_front", "max_res": "1080p", "type": "camera" },
       { "id": "screen_share", "max_res": "4k", "type": "desktop" }
    ]
  }
}
```

#### 消息类型: `cmd_start` (Core -> Sender)
通知 Sender 启动某个特定的视频源。
```json
{
  "type": "cmd_start",
  "params": {
    "source_id": "cam_front", // 关键：指定启动哪个源
    "rtmp_url": "rtmp://192.168.1.100/live/raspi_01_cam_front", // URL 必须包含 source_id 以防冲突
    "resolution": "1280x720", 
    "bitrate": "2000k"
  }
}
```

#### 消息类型: `cmd_stop` (Core -> Sender)
通知 Sender 停止某个源。
```json
{ 
  "type": "cmd_stop",
  "params": {
    "source_id": "cam_front"
  }
}
```

---

### 3.3 UDP 发现协议

**Port**: 9999 (Multicast/Broadcast)

**Sender Request**:
```json
{ "magic": "lan_video_discovery_v1" }
```

**Core Response**:
```json
{
  "service": "lan_video_core",
  "ip": "192.168.1.100",
  "port": 8000
}
```

---

### 3.4 SRS 回调 (Webhook)

**SRS -> Core**

#### `POST /api/hooks/on_close`
当客户端断开连接时触发。

**Body**:
```json
{
  "action": "on_close",
  "client_id": "34522",
  "ip": "192.168.1.105",
  "vhost": "__defaultVhost__",
  "app": "live",
  "stream": "raspi_01_cam_front_360p" 
}
```
