# scripts 目录说明

这里放的是 MarkCompose 的**实际命令实现**，根目录只保留一个统一入口：`./markcompose.sh`。

## 目录结构

- `markcompose.sh`：子命令分发器（`init-site` / `start` / `build` / `stop`）
- `init_site.sh`：初始化 `hugo-site` 骨架
- `start.sh`：启动流程实现
- `build.sh`：构建与发布流程实现
- `stop.sh`：停止流程实现
- `lib/`：共享 shell 模块

## `lib/` 模块职责

- `common.sh`：仓库路径、输出样式、基础校验
- `env.sh`：`.env.runtime` 生成与加载
- `downloads.sh`：下载与归档解压
- `resources.sh`：默认 editor / watcher 资源解析
- `build_helpers.sh`：Hugo 构建、发布、布局同步
- `waline.sh`：Waline SQLite seed 检查与导入
- `watcher.sh`：markwatch 启停与后台命令拼装

## 设计约束

- 用户只需要记住 `./markcompose.sh <command>`
- `scripts/` 内脚本按职责拆分，避免单文件臃肿
- adapter 相关逻辑独立放在 `./adapter/`，不混进常规命令目录
- 运行时状态仍写回仓库根目录：`.env.runtime`、`.markwatch.pid`、`.markwatch.log`

## 调试小抄

```bash
./markcompose.sh help
./markcompose.sh start --help
./markcompose.sh build --help
./markcompose.sh stop --help
```

如果你需要并行开一个临时验证栈，又不想碰当前运行中的容器，可以临时指定：

```bash
MARKCOMPOSE_COMPOSE_PROJECT_NAME=markcompose_validate ./markcompose.sh start ...
```

这招很省事，尤其适合做本地回归，不然一个固定项目名就容易把现成服务撞得一脸懵。