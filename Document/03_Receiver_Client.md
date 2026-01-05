# 组件方案三：接收端客户端 (Receiver Client)

## 1. 组件定位
接收端是用户交互的核心界面，负责发现网络中的视频源，并提供流畅的多路观看体验。

## 2. 技术架构
- **框架**: Electron (主进程 + 渲染进程)
- **前端栈**: React + Material UI (或 Tailwind CSS)
- **后端逻辑**: Python 子进程 (可选) 或 直接在 Electron Main Process 处理。
  - *注：鉴于本项目协议简单，建议直接用 Electron Main Process (Node.js) 处理 HTTP 请求，减少打包 Python 的复杂度。*
- **播放内核**: Chromium 原生 WebRTC (`<video>` 标签)。

## 3. 详细设计

### 3.1 界面布局 (UI Layout)
采用 **Dashboard** 风格设计：
1.  **左侧/顶部导航栏**:
    - "发现列表": 自动刷新显示局域网内所有 Sender。
    - "设置": 核心服务地址配置 (支持自动发现或手动输入)。
2.  **主内容区 (Video Grid)**:
    - 动态网格布局 (CSS Grid)。
    - 支持 1x1, 2x2, 或自定义拖拽布局。
    - 每个格子是一个播放容器。

### 3.2 播放逻辑
1.  **加载**: 用户将某个 Sender 从列表拖入格子 (或点击“播放”)。
2.  **请求**: Electron 向 Core 发送 `POST /api/play/{id}`。
3.  **拉流**: 收到返回的 `webrtc://...` 地址。
4.  **解码**: 使用 `srs.sdk.js` (SRS 官方库) 或原生 RTCPeerConnection 进行播放。

```javascript
// 播放器组件核心逻辑
const startPlay = async (url) => {
    const pc = new RTCPeerConnection();
    pc.addTransceiver('audio', {direction: 'recvonly'});
    pc.addTransceiver('video', {direction: 'recvonly'});
    
    // SRS 交换 Offer/Answer 逻辑...
    // ...
    
    videoRef.current.srcObject = stream;
};
```

### 3.3 性能优化
- **硬解码**: Electron 默认开启 GPU 加速，确保 H.264 解码不占用过多 CPU。
- **自动静音**: 浏览器策略要求自动播放必须 Mute，需在 UI 上提供音量开关。
- **丢包重连**: 监听 WebRTC 状态 `connectionStateChange`，若断开自动重新请求 API 获取新地址。

### 3.4 扩展功能
- **全屏模式**: 双击某个格子全屏。
- **状态指示**: 在视频角标显示当前的码率和分辨率 (通过 WebRTC `getStats()` API 获取)。

## 4. 打包与发布
- 工具: `electron-builder`
- 产物: `.exe` (Windows), `.dmg` (macOS), `.AppImage` (Linux)
- 依赖: 需将 Core Service 地址配置项暴露在 `config.json` 中，以便在不同网络环境部署。
