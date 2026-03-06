# 06 Waline 评论系统配置总结

## 1. 当前接入方式总览

本项目的 Waline 不是直接暴露独立端口给浏览器，而是走 `nginx` 反代，统一挂在博客端口下。

当前访问关系：

- 博客首页：`http://127.0.0.1:<HOST_PORT>/`
- Waline 管理后台：`http://127.0.0.1:<HOST_PORT>/waline/ui`
- Waline 前端服务基址：`/waline`
- 兼容直连 API 路径：`/api/`

这套做法的好处很直接：

- 前台页面和评论服务同域，少踩跨域坑
- 主题里可以直接写相对地址 `serverURL = "/waline"`
- 上线时只需要把博客域名配对，省一个单独评论域名的维护成本

## 2. 容器与代理链路

配置来源：`docker-compose.yml` + `nginx/default.conf`

### 2.1 Waline 容器

`docker-compose.yml` 中的 `waline` 服务：

- 镜像：`lizheming/waline:latest`
- 容器内部端口：`8360`
- 数据目录：`/app/data`
- 挂载卷：`waline_data`

这意味着：

- 评论数据默认放在 Docker volume `waline_data` 中
- 执行 `./markcompose.sh stop` 不会删评论数据
- 执行 `./markcompose.sh stop -v` 会连卷一起删掉，评论库也会被清空

这条别忘。删卷一时爽，评论全没了更爽，钱包没哭你先哭。

### 2.2 Nginx 代理规则

`nginx/default.conf` 中有两段和 Waline 相关的代理：

#### `location /waline/`

用途：

- 代理 Waline 管理后台 `.../waline/ui`
- 代理以 `/waline/` 开头的 Waline 请求

关键转发头：

- `Host`
- `X-Real-IP`
- `X-Forwarded-For`
- `X-Forwarded-Proto`
- `X-Forwarded-Host`

#### `location /api/`

用途：

- 兼容 Waline 管理后台或前端直接访问 `/api/` 路径

这个兼容入口很重要。否则后台地址看着能开，实际接口请求却跑偏，就会出现“页面像活着，功能像去世了”的尴尬场面。

## 3. 运行时环境变量

Waline 相关环境变量由 `docker-compose.yml` 注入，推荐写在项目根目录 `.env` 中，再由 `markcompose.sh start` 合并到 `.env.runtime`。

### 3.1 必填/强烈建议配置

#### `WALINE_JWT_TOKEN`

用途：

- Waline 后台登录和鉴权使用的 JWT 密钥

建议：

- 生产环境必须配置
- 使用足够长的随机字符串
- 不要继续用默认值 `change-this-jwt-token`

#### `HUGO_BASE_URL`

用途：

- Hugo 站点的公开基址
- 同时作为 Waline 的 `SITE_URL` 默认值

建议：

- 本地可以是 `http://127.0.0.1:8080/`
- 线上必须改成真实公网域名，例如 `https://blog.example.com/`

这个值偷懒不改，后面 canonical、OG、评论后台跳转、回调地址，可能一起给你表演集体跑偏。

### 3.2 可选配置

#### `WALINE_SITE_NAME`

用途：

- Waline 后台显示的站点名称

默认值：

- `Blog Comments`

#### `WALINE_SERVER_URL`

用途：

- 显式指定 Waline 对外访问基址

默认行为：

- 未设置时，Waline 使用 `HUGO_BASE_URL` 作为 `SITE_URL`

建议：

- 普通同域部署通常不用单独配
- 如果经过 Cloudflare Tunnel 或反代层较多，建议显式设置成公网可访问地址

## 4. Hugo 主题侧配置

配置位置：`hugo-site/hugo.toml`

当前项目已经启用 Waline：

```toml
[params.page.comment.waline]
  enable = true
  serverURL = "/waline"
  lang = ""
  emoji = ["https://unpkg.com/@waline/emojis@1.1.0/weibo"]
```

重点看两项：

- `enable = true`：开启评论系统
- `serverURL = "/waline"`：前端脚本请求走当前站点下的 `/waline`

这也是为什么 Nginx 必须代理 `/waline/`。主题、反代、容器三边得对齐，少一边都能把评论打成哑火状态。

## 5. 启动与初始化步骤

根目录现在统一使用一个入口：`./markcompose.sh`。

- 常规命令实现放在 `scripts/`
- adapter 是可选能力，相关脚本与配置独立放在 `adapter/`

### 5.1 启动服务

不需要 Markdown 适配时，常规启动：

```bash
./markcompose.sh start <markdown_dir>
```

需要先把普通 Markdown 转成 Hugo 更稳当的内容结构时，再显式启用 adapter：

```bash
./markcompose.sh start --content-adapter adapter/prepare_content.sh <markdown_dir>
```

启动后应确认：

- 博客首页可访问
- `http://127.0.0.1:<HOST_PORT>/waline/ui` 可打开
- 文章详情页有评论区域

### 5.2 后台初始化

首次启动后，可访问：

```text
http://127.0.0.1:<HOST_PORT>/waline/ui
```

当前项目的 `markcompose.sh start` 已内置 Waline SQLite seed 初始化逻辑，和是否启用 adapter 无关：

- 当 `waline_data` volume 中 **不存在** 非空的 `waline.sqlite` 时
- `markcompose.sh start` 会自动下载官方 seed 到 `./.runtime/waline.sqlite`
- adapter 只影响 Markdown 内容适配，不影响 Waline 初始化流程
- 然后把 seed 导入 Waline 数据卷，再启动 `waline`/`nginx`

这意味着：

- 首次启动不用再手工导 seed
- 正常 `./markcompose.sh stop -> ./markcompose.sh start` 重启不会覆盖已有数据库
- 已存在用户/评论时，`markcompose.sh start` 只会跳过 seed 导入
- 只有执行 `./markcompose.sh stop -v` 删掉 `waline_data` volume 后，Waline 才会回到“空 seed”状态

### 5.3 官方 seed 库包含什么

当前使用的 seed 来源：

- `https://raw.githubusercontent.com/walinejs/waline/main/assets/waline.sqlite`

根据项目内实际下载结果检查，这个 seed 是一个**空的 SQLite 基础库**，包含：

- `wl_Users`：Waline 用户表
- `wl_Comment`：评论表
- `wl_Counter`：计数/反应表
- `sqlite_sequence`：SQLite 自增主键内部表

初始记录数都是 `0`（内部表除外），也就是说：

- **没有预置管理员账号**
- **没有预置评论内容**
- **没有预置计数数据**

它的作用只是提供 Waline 所需表结构，避免首次启动时报：

- `no such table: wl_Users`
- `no such table: wl_Comment`

所以你可以把它理解成“空仓库模板”，不是“带数据备份包”。真正的用户、评论、计数，都是后续运行过程中写进 `waline_data` volume 的。

### 5.4 常见操作示例

#### 示例 A：首次启动，自动初始化空 Waline 库

```bash
./markcompose.sh start <markdown_dir>
```

预期行为：

- `waline_data` 还没有数据库时，`markcompose.sh start` 自动导入 seed
- 导入后启动 `waline` 与 `nginx`
- 后台入口：`http://127.0.0.1:<HOST_PORT>/waline/ui`

#### 示例 B：正常重启，保留已有 Waline 用户/评论

```bash
./markcompose.sh stop
./markcompose.sh start <markdown_dir>
```

预期行为：

- `markcompose.sh stop` 只停容器，不删 `waline_data`
- `markcompose.sh start` 检测到已有 `waline.sqlite` 后跳过 seed 导入
- 已有用户、评论、计数继续保留

这也是日常重启推荐姿势。别没事上来就 `-v`，那不是勤快，那是手快。

#### 示例 C：明确要清空 Waline 数据，再从空 seed 重建

```bash
./markcompose.sh stop -v
./markcompose.sh start <markdown_dir>
```

预期行为：

- `markcompose.sh stop -v` 删除 `waline_data` volume
- 原有 Waline 用户/评论全部丢失
- 下一次 `markcompose.sh start` 会重新导入一个空 seed 库
- 最终得到的是“表结构完整但没有业务数据”的全新 Waline 状态

适用场景：

- 本地测试想彻底重置评论系统
- 明确知道历史评论和用户都不需要保留

不适用场景：

- 只是想重启服务
- 只是想更新页面或配置
- 只是想排查普通访问异常

## 6. 反代/隧道场景注意事项

如果前面还有 Cloudflare Tunnel、Nginx、Caddy 或其他反代层，至少要保证两件事：

### 6.1 `Host` 传递为公网域名

否则后台生成的地址可能还是内网地址或错误主机名。

### 6.2 `X-Forwarded-Proto` 保持为 `https`

否则 Waline 管理后台可能把接口地址渲染成：

- `http://.../api/`

而不是：

- `https://.../api/`

结果就是浏览器混合内容、跳错协议、后台打不开接口，排查起来又臭又长。

项目里的 `nginx/default.conf` 已经做了这层透传：

- 优先使用上游传入的 `X-Forwarded-Proto`
- 如果没有，则回退到当前请求协议 `$scheme`

## 7. 常见问题与排查顺序

### 7.1 `/waline/ui` 能打开，但评论提交失败

优先检查：

1. `hugo-site/hugo.toml` 中 `serverURL` 是否仍为 `/waline`
2. `nginx/default.conf` 中 `/waline/` 与 `/api/` 代理是否还在
3. 浏览器 Network 中评论请求是否打到当前博客域名
4. Waline 容器日志是否报鉴权或数据库错误

### 7.2 后台能打开，但接口地址变成 `http://`

优先检查：

1. 上游反代是否正确传了 `X-Forwarded-Proto: https`
2. `WALINE_SERVER_URL` 是否需要显式指定为公网 HTTPS 地址

### 7.3 重启后评论数据丢失

优先检查：

1. 是否执行过 `./markcompose.sh stop -v`
2. `waline_data` volume 是否还在
3. 是否误删了容器内 `/app/data` 对应数据

### 7.4 后台报缺表错误

优先检查：

1. Waline 数据库是否初始化
2. 是否需要重新导入 seed SQLite

## 8. 推荐最小配置清单

建议至少在 `.env` 中放这些值：

```env
WALINE_JWT_TOKEN=replace-with-a-long-random-secret
WALINE_SITE_NAME=My Blog Comments
HUGO_BASE_URL=https://blog.example.com/
# WALINE_SERVER_URL=https://blog.example.com/waline
```

补一句落地建议：

- **同域部署**：优先只配 `HUGO_BASE_URL`，最省事
- **多层反代/隧道**：再补 `WALINE_SERVER_URL`
- **生产环境**：一定换掉默认 JWT
- **清理环境**：别乱用 `markcompose.sh stop -v`

能省的咱就省，能避免的坑也别反复交学费。
