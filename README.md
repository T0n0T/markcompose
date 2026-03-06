# Hugo + Nginx MarkCompose

一个面向本地/自托管博客工作流的最小栈：

- Hugo 负责构建静态站点
- Nginx 负责双端口提供博客与编辑器静态资源
- Waline 负责评论系统
- 可选 `markwatch` 负责 Markdown 变更后的自动重建
- 可选 `adapter/` 负责把“普通 Markdown 工作区”转换成 Hugo 更稳当的内容结构

根目录现在只保留一个用户入口：

```bash
./markcompose.sh <command> [args]
```

常用子命令：

- `./markcompose.sh init-site`：初始化 `hugo-site` 骨架，方便先配置站点
- `./markcompose.sh start ...`：启动服务、先构建一次、按需启动 watcher
- `./markcompose.sh build ...`：单次发布构建
- `./markcompose.sh stop ...`：停止容器与 watcher

---

## 1. 这个项目做什么

- 构建博客 HTML：`docker.io/hugomods/hugo:dart-sass`
- 博客站点端口：`HOST_PORT`，默认 `8080`
- 编辑器端口：`EDITOR_PORT`，默认 `8081`
- Markdown 资源目录：`/<ASSETS_DIR>/...`，默认 `/_assets/`
- Waline API / 管理后台：挂在博客端口下的 `/waline/`
- 可选自动构建：`markwatch`

### 访问映射

- `http://127.0.0.1:<HOST_PORT>/` -> 博客静态站点
- `http://127.0.0.1:<EDITOR_PORT>/` -> 编辑器静态资源
- `http://127.0.0.1:<HOST_PORT>/<ASSETS_DIR>/...` -> Markdown 管理的资源文件
- `http://127.0.0.1:<HOST_PORT>/waline/` -> Waline API / 管理后台

补一句：编辑器走独立端口，不走 `/editor/` 路径。这点别脑补错，不然你会排查半天自己。 

---

## 2. 要求

- Docker + `docker compose`
- `bash`
- `realpath`
- `tar`（使用默认 editor / watcher 资源时需要）
- `curl` 或 `wget`（首次下载默认资源时需要）

---

## 3. 快速开始

### 3.1 先初始化站点骨架（推荐第一次用时执行）

```bash
cd markcompose
./markcompose.sh init-site
```

如果 `hugo-site/hugo.toml` 不存在，这会用 Hugo Docker 镜像补齐站点骨架；如果 `hugo-site/hugo.toml` 已存在，则不会覆盖现有站点，只会同步复用 layouts。这样用户可以先改站点配置、菜单、主题参数。

### 3.2 最快启动

```bash
./markcompose.sh start <markdown_dir>
```

这会做几件事：

1. 校验参数和依赖
2. 准备默认 editor / watcher 资源（如果你没自定义）
3. 生成 `.env.runtime`
4. 跑一次发布构建
5. 启动 `waline` + `nginx`
6. 按需启动 watcher

### 3.3 最常见的四个命令

```bash
./markcompose.sh init-site
./markcompose.sh start <markdown_dir>
./markcompose.sh build
./markcompose.sh stop
```

### 3.4 如果你的 Markdown 仓库不需要 adapter

那就**别开**。adapter 是可选能力，不是硬性仪式感。

```bash
./markcompose.sh start <markdown_dir>
```

### 3.5 如果你的 Markdown 仓库需要先转换再给 Hugo

```bash
./markcompose.sh start --content-adapter adapter/prepare_content.sh <markdown_dir>
```

---

## 4. 配置速查

推荐先复制：

```bash
cp .env.example .env
```

然后按需修改。

### 4.1 `.env` 和 `.env.runtime` 的关系

- `.env`：可选的**基线配置**，适合放长期稳定的环境变量
- `.env.runtime`：运行时文件，由 `markcompose.sh start` 生成/覆盖

`markcompose.sh start` 会：

1. 读取 `.env`（如果存在）
2. 生成 `.env.runtime`
3. 写入运行时托管字段，例如：
   - `MARKDOWN_DIR`
   - `EDITOR_STATIC_DIR`
   - `HOST_PORT`
   - `EDITOR_PORT`
   - `ADAPTER_SCRIPT`

也就是说：

- 你该长期维护的是 `.env`
- 不要手改 `.env.runtime` 指望它永远听话

### 4.2 常用环境变量

`.env.example` 里目前最值得关心的是：

- `HOST_PORT`：博客端口，默认 `8080`
- `EDITOR_PORT`：编辑器端口，默认 `8081`
- `ASSETS_DIR`：Markdown 资源目录，默认 `_assets`
- `HUGO_BASE_URL`：Hugo 构建时的公开基址
- `WALINE_JWT_TOKEN`：Waline 生产环境必须设置
- `WALINE_SITE_NAME`：Waline 后台显示站点名
- `WALINE_SERVER_URL`：Waline 对外访问基址覆盖项

---

## 5. 启动与初始化方式

### 5.1 初始化 hugo-site

```bash
./markcompose.sh init-site
```

适用场景：

- 第一次拉下仓库，还没准备 `hugo-site`
- 想先配置 Hugo 站点，再接 Markdown 仓库

注意：

- 如果 `./hugo-site/hugo.toml` 已存在，这个命令不会覆盖现有站点，只会同步复用 layouts

### 5.2 默认模式

```bash
./markcompose.sh start [options] <markdown_dir>
```

默认模式使用仓库内缓存或自动下载的资源：

- editor: [markflow](https://github.com/T0n0T/markflow)
- watcher: [markwatch](https://github.com/T0n0T/markwatch)

默认查找顺序：

1. `./.runtime/` 里的本地归档
2. GitHub release `latest`
3. 解压到 `./.runtime/`

默认下载地址：

- `https://github.com/T0n0T/markflow/releases/latest/download/markflow-dist.tar.gz`
- `https://github.com/T0n0T/markwatch/releases/latest/download/markwatch-<target>.tar.gz`

### 5.3 自定义 watcher

```bash
./markcompose.sh start --use-custom-watcher <watcher_cmd> <markdown_dir>
```

### 5.4 自定义 editor

```bash
./markcompose.sh start --use-custom-editor <editor_static_dir> <markdown_dir>
```

### 5.5 自定义 editor + 自定义 watcher

```bash
./markcompose.sh start \
  --use-custom-editor <editor_static_dir> \
  --use-custom-watcher <watcher_cmd> \
  <markdown_dir>
```

### 5.6 常用选项

- `-a, --assets-dir <dir>`：资源目录名，默认 `_assets`
- `--content-adapter <script>`：启用 adapter
- `-p, --host-port <port>`：博客端口，默认 `8080`
- `--editor-port <port>`：编辑器端口，默认 `8081`
- `--no-watch`：不启动 watcher
- `--debounce-ms <num>`：默认 watcher 的 debounce，默认 `800`
- `--reconcile-sec <num>`：默认 watcher 的 reconcile，默认 `600`
- `--watch-log-level <level>`：默认 watcher 日志级别，默认 `info`

### 5.7 watcher 注意事项

- 自定义 watcher 模式下，`--debounce-ms` / `--reconcile-sec` / `--watch-log-level` 会被忽略
- 自定义 watcher 最好保持为**单个前台命令**
- 避免在 watcher 命令里乱塞 `&&`、`|`、结尾 `&`
- 不然 `./markcompose.sh stop` 清理进程时会很烦

---

## 6. 最常用示例

```bash
# 初始化站点骨架
./markcompose.sh init-site

# 默认启动
./markcompose.sh start /data/blog/markdown

# 启用 adapter
./markcompose.sh start --content-adapter adapter/prepare_content.sh /data/blog/markdown

# 自定义资源目录
./markcompose.sh start --assets-dir images /data/blog/markdown

# 自定义 watcher
./markcompose.sh start --use-custom-watcher "markwatch --some-flag value" /data/blog/markdown

# 自定义 editor
./markcompose.sh start --use-custom-editor /data/editor/dist /data/blog/markdown

# 构建一次
./markcompose.sh build

# 停止
./markcompose.sh stop

# 停止并删卷（会清空 Waline 数据）
./markcompose.sh stop -v
```

---

## 7. Adapter 什么时候该用

如果你的 Markdown 仓库已经符合 Hugo 直接消费的结构，可以不启用 adapter。

如果你的仓库更像“普通写作目录”，比如：

- 根目录散落文章
- 需要自动补 `title/date/draft/slug`
- 需要 sidecar 覆盖元数据
- 需要把 `*.md` 相对链接改写为 Hugo `relref`

那 adapter 会更省心。

### Adapter 相关文件

- 入口：`adapter/prepare_content.sh`
- 实现：`adapter/content_adapter.py`
- 配置：`adapter/content-adapter.toml`

### `MARKDOWN_DIR` 典型结构

```text
<markdown_dir>/
├── _assets/
│   └── ...
├── 2026-03-01-hello.md
├── 2026-03-01-hello.md.meta.yml
├── notes/
│   ├── index.md
│   ├── deep-dive.md
│   └── deep-dive.md.meta.yml
└── projects/
    └── alpha.md
```

### Adapter 默认行为

- 根目录 markdown 会映射到 `default_section`，默认 `posts`
- 子目录 markdown 保持相对路径
- 支持 sidecar：`*.meta.yaml` / `*.meta.yml`
- 缺失字段时自动推断 `title/date/draft/slug`
- 站内 `*.md` 链接可改写成 Hugo `relref`
- 默认忽略：`.git`、`.runtime`、资源目录 `ASSETS_DIR`

更多规则细节见：

- `docs/03-content-adapter规则与元数据覆盖.md`

---

## 8. 构建流程

### 8.1 触发单次构建

```bash
./markcompose.sh build
```

### 8.2 这不是裸 `hugo`

`./markcompose.sh build` 是完整发布流水线，不只是敲一下 Hugo：

1. 如果启用了 adapter，先生成 `.runtime/content-adapted`
2. 构建到临时 staging 目录
3. 做 gate 检查（例如必须存在 `index.html`）
4. 用 staging 结果整体替换发布卷内容

也就是说：

- 它会清理旧产物
- 会避免残留脏文件
- watcher 触发的也是同一条构建链路

### 8.3 Hugo 启动补充

- 如果 `./hugo-site` 不存在，构建流程仍会自动执行 `hugo new site hugo-site` 兜底
- 但更推荐你先手动执行 `./markcompose.sh init-site`，这样可以在首次启动前先配置站点
- 每次构建前，`./hugo-reuse/layouts/` 会同步到 `./hugo-site/layouts/`

---

## 9. Waline 配置与数据行为

### 9.1 推荐配置

建议在 `.env` 中设置：

- `WALINE_JWT_TOKEN`
- `WALINE_SITE_NAME`
- `HUGO_BASE_URL`
- `WALINE_SERVER_URL`（有 Tunnel / 复杂反代时再用）

### 9.2 管理后台地址

启动后访问：

```text
http://127.0.0.1:<HOST_PORT>/waline/ui
```

### 9.3 seed 初始化逻辑

`./markcompose.sh start` 会自动处理 Waline SQLite seed：

- seed 来源：`https://raw.githubusercontent.com/walinejs/waline/main/assets/waline.sqlite`
- 本地缓存：`./.runtime/waline.sqlite`
- 导入条件：Waline 卷里还没有非空数据库

这个 seed 是**空表结构模板**，不是评论备份包。它包含表，不包含你宝贵的用户和评论。

### 9.4 三种常见场景

#### 首次启动

```bash
./markcompose.sh start <markdown_dir>
```

结果：

- 若数据库不存在，自动导入 seed
- 然后启动 `waline` + `nginx`

#### 正常重启，不丢评论

```bash
./markcompose.sh stop
./markcompose.sh start <markdown_dir>
```

结果：

- `waline_data` volume 保留
- 已有数据库保留
- 不会重复覆盖评论数据

#### 明确要清空 Waline 数据

```bash
./markcompose.sh stop -v
./markcompose.sh start <markdown_dir>
```

结果：

- 删除 `waline_data`
- 下次启动重新导入空 seed
- 原有评论和用户都会消失

所以这条命令别手滑，真会把数据送走。

更完整的 Waline 说明见：

- `docs/06-Waline评论系统配置总结.md`

---

## 10. 停止服务

```bash
./markcompose.sh stop
```

删除命名卷：

```bash
./markcompose.sh stop -v
```

`stop` 做的事：

- `docker compose down`
- 如果有 watcher PID 文件，则额外停止后台 watcher

---

## 11. 项目结构速览

- `markcompose.sh`：根目录唯一入口
- `scripts/init_site.sh`：初始化 `hugo-site` 的实现
- `scripts/`：`start/build/stop` 的实际实现
- `scripts/lib/`：共享 shell 模块
- `adapter/`：可选内容适配器
- `.env`：可选基线配置
- `.env.runtime`：运行时配置文件
- `.runtime/`：下载缓存、解压资源、适配输出
- `.markwatch.pid` / `.markwatch.log`：watcher 状态文件
- `docker-compose.yml`：容器编排
- `hugo-site/hugo.toml`：Hugo 主配置
- `hugo-reuse/layouts/`：构建前同步到站点 layouts 的复用模板
- `docs/`：项目说明文档

如果你想看脚本内部职责拆分，直接看：

- `scripts/README.md`

---

## 12. 已知约束

- 目前默认资源流程主要面向 Linux 主机
- 不运行 `hugo server`，而是“构建后静态托管”模式
- `./markcompose.sh start` 不接受包含空白字符的关键路径
- 默认 watcher 包只支持 Linux `amd64` / `arm64`
- 新引导出的 `hugo-site` 只是 Hugo 骨架，主题和页面模板要你自己补
- 图片/链接路径改写只处理站内约定范围，不会替你魔法修复所有野路子路径
- 当前构建/发布是全站构建，不是跨运行增量构建

---

## 13. 进一步阅读

- `docs/01-系统结构与目录职责.md`
- `docs/02-启动与构建链路注意事项.md`
- `docs/03-content-adapter规则与元数据覆盖.md`
- `docs/04-路由与链接问题排查.md`
- `docs/05-日常运维与发布检查清单.md`
- `docs/06-Waline评论系统配置总结.md`
