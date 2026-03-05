# 03 content-adapter 规则与元数据覆盖

## 1. 输入输出定位

- 输入：`MARKDOWN_DIR` 下普通 Markdown 工作区
- 输出：`.runtime/content-adapted`（默认）
- 根目录 `*.md` 会映射到 `default_section`（默认 `posts/`）
- 子目录 `*.md` 维持相对路径（例如 `notes/a.md -> notes/a.md`）

## 2. front matter 合并优先级

最终字段来源优先级（高 -> 低）：

1. sidecar（`*.meta.yaml` / `*.meta.yml`）
2. 原文件 front matter（YAML/TOML）
3. 自动推断（title/date/draft/slug）

`title/date/draft/slug` 会被补齐，保证主题渲染稳定。

## 3. 自动推断规则

- `title`：
  - 优先正文第一个 H1
  - 否则回退文件名（会尝试去掉日期前缀）
- `date`：
  - 优先文件名日期前缀（`YYYY-MM-DD` / `YYYY_MM_DD`）
  - 否则用文件 mtime（UTC，秒级）
- `slug`：
  - 优先文件名转 slug（去日期前缀、转小写、替换非法字符）
  - ASCII 失败时保留 Unicode 兜底
- `draft`：
  - 使用 `content-adapter.toml` 的 `default_draft`（默认 `false`）

## 4. H1 去重规则

`strip_first_h1 = true` 时，只有在“首个 H1 与最终 `title` 一致且是正文首个非空行”才会移除，避免误删正文结构。

## 5. `*.md` 链接改写规则

开启 `rewrite_md_links = true` 时：

- 仅改写指向站内 `*.md` 的相对链接（含引用式与内联式）
- 改写目标：Hugo `relref`
- 不改写：
  - 图片链接
  - 绝对 URL / 协议 URL / `//` URL
  - `#anchor`、根路径 `/foo`
  - shortcodes（`{{< ... >}}` / `{{% ... %}}`）
  - 无法解析到目标文件的链接

## 6. 目录扫描与忽略

- 默认跳过资源目录 `ASSETS_DIR`（默认 `_assets`）
- 默认忽略目录：`.git`、`.runtime`
- 只处理 `*.md` 文件

## 7. 实操建议

- 需要精确控制发布时间、分类、标签时，优先写 sidecar，不要依赖推断
- 团队约定文件名含日期，可提升 `date` 结果稳定性
- 链接大量互引的仓库，建议保留 `rewrite_md_links = true`

