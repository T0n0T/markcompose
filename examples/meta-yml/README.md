# `*.meta.yml` 用法示例

这个目录演示内容适配器如何使用 sidecar 元数据文件（`*.meta.yml`）覆盖自动推断字段或原 front matter。

它的目标是说明“覆盖机制怎么工作”，不是列出当前主题所有可用字段。若需要字段推荐和主题映射，请同时参考：

- `docs/03-content-adapter规则与元数据覆盖.md`
- `docs/07-meta-yml推荐字段与主题映射.md`

## 目录说明

- `input/recommended-template.md`：推荐模板对应的 Markdown 正文
- `input/recommended-template.md.meta.yml`：推荐字段模板 sidecar 示例

## 本地验证

在仓库根目录执行：

```bash
./adapter/prepare_content.sh examples/meta-yml .runtime/examples-meta-yml adapter/content-adapter.toml
```

检查输出：

```bash
sed -n '1,80p' .runtime/examples-meta-yml/posts/no-frontmatter.md
sed -n '1,80p' .runtime/examples-meta-yml/posts/with-frontmatter.md
sed -n '1,120p' .runtime/examples-meta-yml/posts/recommended-template.md
```

你会看到：

- `title/date/draft/slug` 都会存在
- `*.meta.yml` 中声明的字段会覆盖自动推断或原 front matter
- 指向 `*.md` 的链接会被改写为 Hugo `relref`

## 这个示例已经覆盖了什么

当前示例覆盖了两条主路径：

1. 无 front matter 的 Markdown，由自动推断补齐基础字段，再由 sidecar 覆盖
2. 已有 front matter 的 Markdown，由 sidecar 覆盖同名字段

另外也顺带展示了：

- 自定义字段可以进入最终 front matter
- 站内 `*.md` 链接会被改写
- 一份更接近实际使用的推荐 sidecar 模板

## 这个示例没有刻意覆盖什么

如果你问“它是不是完整规范”，答案是不算。当前示例没有专门演示这些边界：

- `*.meta.yaml` 与 `*.meta.yml` 双后缀优先级
- TOML front matter 被 sidecar 覆盖
- 非法 sidecar 的报错行为
- 嵌套对象的浅合并边界
- 当前主题实际会消费哪些字段

也就是说：

- 它适合说明 sidecar 覆盖机制
- 不适合单独拿来当“完整字段字典”

## 一个关键边界：sidecar 是浅合并

当前 adapter 对 sidecar 的合并是顶层覆盖，不是深合并。

例如原 front matter：

```yaml
comment:
  enable: true
  waline:
    enable: true
    serverURL: /waline
```

如果 `*.meta.yml` 写成：

```yaml
comment:
  enable: false
```

最终大概率会变成：

```yaml
comment:
  enable: false
```

而不是“保留原 waline 配置，只把 enable 改成 false”。

因此像下面这些对象字段，如果要覆盖，建议写完整对象：

- `toc`
- `math`
- `share`
- `comment`
- `mapbox`
- `library`
- `seo`

## 推荐字段模板

仓库里已经提供了一个可直接运行的样例：

- `recommended-template.md`
- `recommended-template.md.meta.yml`

如果你想在当前项目里写一份“够用又不折腾”的 sidecar，可以从这版开始：

```yaml
title: 文章标题
date: 2026-03-07T12:00:00Z
draft: false
slug: article-slug

description: 一句话摘要
tags:
  - Hugo
  - Markdown
categories:
  - 技术

author: Your Name
subtitle: 可选副标题
featuredimage: /images/article-cover.jpg

toc: true
comment: true
```

若要使用更完整的主题字段，请看：

- `docs/07-meta-yml推荐字段与主题映射.md`
