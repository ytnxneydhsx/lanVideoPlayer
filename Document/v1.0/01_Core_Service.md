# 组件方案一：核心服务 (Core Service)

## 1. 组件定位
核心服务是系统的中心控制器，负责维护全局状态。它必须轻量、高并发且稳定。

## 2. 技术架构
- **语言**: Python 3.10+
- **Web 框架**: FastAPI (异步高性能)
- **协议**: 
  - HTTP/REST (供 Receiver 查询)
  - WebSocket (供 Sender 保持长连接与信令)
  - UDP (用于局域网服务发现)

## 3. 详细设计

### 3.1 模块结构
```text
core_service/
├── main.py            # FastAPI 入口
├── connection_mgr.py  # WebSocket 连接与状态管理器
├── discovery.py       # UDP 广播监听线程
└── models.py          # Pydantic 数据模型
```

### 3.2 UDP 自动发现模块 (`discovery.py`)
- **原理**: 启动一个守护线程 (Daemon Thread)，绑定 `0.0.0.0:9999` (UDP)。
- **逻辑**:
  1. 循环监听 `recvfrom`。
  2. 收到特定 Magic Word 后，获取本机局域网 IP。
  3. 向发送者 IP 单播回复 JSON: `{"ip": "192.168.x.x", "port": 8000}`。
- **鲁棒性**: 需处理多网卡 IP 选择问题，优先返回非回环(127.0.0.1)地址。

### 3.3 连接管理模块 (`connection_mgr.py`)
维护两个核心字典：
1.  `active_connections: Dict[str, WebSocket]`: 存储活跃的 WebSocket 实例。
2.  `senders_info: Dict[str, dict]`: 存储业务数据（状态、配置、推流地址）。

**状态机流转**:
- `offline` -> (WS Connect) -> `idle`
- `idle` -> (Start Cmd) -> `streaming`
- `streaming` -> (Stop Cmd / Error) -> `idle`
- Any -> (WS Disconnect) -> `offline`

### 3.4 API 接口定义

| 方法 | 路径 | 描述 |
| :--- | :--- | :--- |
| **GET** | `/api/streams` | 获取所有在线设备列表及状态 |
| **POST** | `/api/play/{id}` | 请求播放。若设备在 idle，触发推流指令 |
| **WS** | `/ws/sender/{id}` | Sender 专用信令通道 |

### 3.5 信令定义 (WebSocket Payload)

**Core -> Sender (指令)**:
```json
{
  "type": "cmd_start",
  "params": {
    "rtmp_url": "rtmp://192.168.1.100/live/cam01",
    "resolution": "1920x1080",
    "fps": 30
  }
}
```

**Sender -> Core (反馈)**:
```json
{
  "type": "status_update",
  "state": "streaming" // or "idle", "error"
}
```

## 4. 部署与运行
建议通过 Docker Compose 与 SRS 一同部署，确保网络互通。
```yaml
services:
  core:
    build: .
    network_mode: "host" # 必须使用 host 模式以支持 UDP 广播
  srs:
    image: ossrs/srs:5
    ports:
      - "1935:1935"
      - "1985:1985"
      - "8080:8080"
```
