# V1.5 核心实现指南：Transcoder Manager

## 1. 模块职责
`Transcoder Manager` 是 Core Service 的新组件，专门负责 FFmpeg 进程的生命周期管理。

## 2. 数据结构设计

```python
class TranscodeTask:
    source_id: str      # 原始 Sender ID
    quality: str        # 目标画质 (e.g., "360p")
    process: Popen      # FFmpeg 子进程句柄
    last_active: float  # 最后一次有用户观看的时间戳
    output_url: str     # 推流地址
```

在全局变量中维护一个任务字典：
`transcode_tasks: Dict[str, TranscodeTask]` (Key 为 `source_id + quality`)

## 3. FFmpeg 命令模板
这是实现转码的核心魔法。我们使用 `libx264` 的极速模式。

```bash
ffmpeg -v error -i rtmp://localhost/live/{source_id} \
  -c:v libx264 -preset ultrafast -tune zerolatency \
  -vf scale=-2:360  # 核心：缩放到 360p 高度，宽度自适应
  -b:v 400k         # 核心：限制码率为 400kbps
  -c:a aac -b:a 64k \
  -f flv rtmp://localhost/live/{source_id}_360p
```

## 4. 关键逻辑伪代码

### 4.1 启动转码
```python
async def ensure_transcoding(source_id: str, quality: str):
    task_key = f"{source_id}_{quality}"
    
    # 1. 如果任务已存在且活着，更新活跃时间并返回
    if task_key in tasks:
        tasks[task_key].last_active = time.time()
        return tasks[task_key].output_url
        
    # 2. 否则，启动新进程
    cmd = build_ffmpeg_cmd(source_id, quality)
    proc = subprocess.Popen(cmd)
    
    # 3. 记录任务
    tasks[task_key] = TranscodeTask(proc, ...)
    
    return build_output_url(source_id, quality)
```

### 4.2 看门狗 (Watchdog)
启动一个后台线程，每 5 秒运行一次：
```python
def cleanup_loop():
    now = time.time()
    for key, task in tasks.items():
        if now - task.last_active > 30: # 30秒无人观看
            task.process.terminate()
            del tasks[key]
            print(f"Stopped idle transcoder: {key}")
```

## 5. 风险控制
- **死循环风险**: 如果 SRS 挂了，FFmpeg 可能会无限报错重启。需要增加“重启计数器”，超过 3 次失败则放弃。
- **僵尸进程**: Core 服务退出时，必须捕获 `SIGINT` 信号，遍历 `tasks` 杀掉所有残留的 FFmpeg 子进程。
