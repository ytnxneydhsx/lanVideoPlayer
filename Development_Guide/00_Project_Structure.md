# 项目物理结构与代码规范 (Project Structure)

> **致开发者**: 本文档定义了 `lanVideoPlayer` 的工程骨架。所有代码提交必须严格遵循此结构，严禁随意在根目录创建文件。

## 1. 根目录结构 (Root Directory)

```text
lanVideoPlayer/
├── .github/                # GitHub Actions CI/CD 配置
├── Document/               # 架构设计与产品文档 (V1.0, V1.5)
├── Development_Guide/      # 开发实施指南 (你现在看的地方)
├── logs/                   # [新增] 全局日志归档目录 (GitIgnore 但必须存在)
│   ├── core/               # Core 服务日志
│   ├── sender/             # Sender 客户端日志
│   └── receiver/           # Receiver 应用日志
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

```text
src/core/
├── main.py                 # 启动入口 (FastAPI app)
├── api/                    # HTTP API 路由
│   ├── routes.py
│   └── models.py           # Pydantic 数据模型 (Register, PlayRequest)
├── services/
│   ├── connection_mgr.py   # WebSocket 连接管理器
│   ├── transcoder_mgr.py   # FFmpeg 进程管理器 (V1.5 核心)
│   └── discovery.py        # UDP 广播响应逻辑
├── config.yaml             # 配置文件 (端口、SRS地址等)
└── requirements.txt
```

### 2.2 Sender Client (`src/sender`)
负责采集与推流。

```text
src/sender/
├── main.py                 # 启动入口
├── ui/                     # TUI 界面逻辑 (Rich/Textual)
├── hardware/               # 摄像头枚举与控制
├── pipeline/
│   ├── ffmpeg_wrapper.py   # FFmpeg 子进程封装
│   └── signaling.py        # WebSocket 客户端
└── requirements.txt
```

### 2.3 Receiver App (`src/receiver`)
负责播放与交互。

```text
src/receiver/
├── main/                   # Electron 主进程
├── renderer/               # React 渲染进程
│   ├── components/         # UI 组件 (VideoGrid, QualitySelector)
│   ├── api/                # HTTP Client (axios)
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
系统采用 **Console + File** 双输出策略。

**文件存储规范**:
- 根目录: `logs/{module_name}/`
- 命名格式: `{module_name}_{YYYY-MM-DD}.log` (按天轮转)
  - 例如: `logs/core/core_2026-01-06.log`
- 轮转策略: 保留最近 7 天日志，超过自动删除。

**格式标准**:
`[TIME] [LEVEL] [MODULE] - Message`
示例：
`2026-01-06 12:00:01 [INFO] [Core.Transcoder] - Started FFmpeg for cam01_360p (PID: 1024)`

**实现建议**:
- Python: 使用 `loguru` (强烈推荐) 或内置 `logging` 模块配置 `RotatingFileHandler`。
- Electron: 使用 `electron-log`。

---

**Next Step**: 请阅读各模块的详细开发指南 (`01_Sender_Dev_Guide.md`, 等)。
