# 项目物理结构与代码规范 (Project Structure)

> **致开发者**: 本文档定义了 `lanVideoPlayer` 的工程骨架。所有代码提交必须严格遵循此结构，严禁随意在根目录创建文件。

## 1. 根目录结构 (Root Directory)

```text
lanVideoPlayer/
├── .github/                # GitHub Actions CI/CD 配置
├── Document/               # 架构设计与产品文档 (V1.0, V1.5)
├── Development_Guide/      # 开发实施指南 (你现在看的地方)
├── src/                    # 核心源代码 (Monorepo 风格)
│   ├── core/               # Core Service (Python)
│   ├── sender/             # Sender Client (Python)
│   └── receiver/           # Receiver App (Electron/React)
├── deploy/                 # 部署相关 (Docker, SRS Conf)
├── tests/                  # 集成测试用例
├── .gitignore
└── README.md
```

## 2. 模块详细结构 (Module Details)

### 2.1 Core Service (`src/core`)
负责信令交互与转码调度。
**部署**: 通常部署在高性能服务器或云主机上。

```text
src/core/
├── logs/                   # [新增] 本地日志目录 (GitIgnore)
│   └── core_2026-01-06.log
├── main.py                 # 启动入口 (FastAPI app)
├── api/                    # HTTP API 路由
│   ├── routes.py
│   └── models.py           # Pydantic 数据模型
├── services/
│   ├── connection_mgr.py   # WebSocket 连接管理器
│   ├── transcoder_mgr.py   # FFmpeg 进程管理器
│   └── discovery.py        # UDP 广播响应逻辑
├── config.yaml             # 配置文件
└── requirements.txt
```

### 2.2 Sender Client (`src/sender`)
负责采集与推流。
**部署**: 运行在树莓派、工控机等边缘设备上。

```text
src/sender/
├── logs/                   # [新增] 本地日志目录 (GitIgnore)
│   └── sender_2026-01-06.log
├── main.py                 # 启动入口
├── ui/                     # TUI 界面逻辑
├── hardware/               # 摄像头枚举与控制
├── pipeline/
│   ├── ffmpeg_wrapper.py   # FFmpeg 子进程封装
│   └── signaling.py        # WebSocket 客户端
└── requirements.txt
```

### 2.3 Receiver App (`src/receiver`)
负责播放与交互。
**部署**: 运行在用户 PC 或 Mac 上。

```text
src/receiver/
├── logs/                   # [新增] 本地日志目录 (Electron UserData)
├── main/                   # Electron 主进程
├── renderer/               # React 渲染进程
│   ├── components/         # UI 组件
│   ├── api/                # HTTP Client
│   └── hooks/              # WebRTC 逻辑封装
├── package.json
└── tsconfig.json
```

## 3. 开发规范 (Conventions)

### 3.1 命名规范
- **Python**: 蛇形命名 (`transcoder_mgr.py`, `start_streaming`)。
- **TypeScript**: 
  - 文件/组件: 帕斯卡命名 (`VideoGrid.tsx`)。
  - 函数/变量: 驼峰命名 (`startPlay`).
- **API 字段**: 统一使用蛇形命名 JSON (`{"source_id": "cam01"}`)。

### 3.2 依赖管理
- **Python**: 每个模块独立 `requirements.txt`。不要搞一个全局的。
- **Node**: 使用 `npm` 或 `yarn`，锁死 `lock` 文件。

### 3.3 日志标准 (Logging)
系统采用 **Console + File** 双输出策略。日志必须**随应用部署**。

**文件存储规范**:
- **Core / Sender**: 存放在模块根目录下的 `logs/` 文件夹中。
- **Receiver (Electron)**: 存放在操作系统的用户数据目录中 (e.g., `%APPDATA%/lanVideoPlayer/logs/`)，不要存放在源码目录。

**轮转策略**:
- 命名格式: `{module_name}_{YYYY-MM-DD}.log`
- 策略: 保留最近 7 天，每日轮转。

**格式标准**:
`[TIME] [LEVEL] [MODULE] - Message`
示例：
`2026-01-06 12:00:01 [INFO] [Core.Transcoder] - Started FFmpeg for cam01_360p (PID: 1024)`

---

**Next Step**: 请阅读各模块的详细开发指南 (`01_Sender_Dev_Guide.md`, 等)。
