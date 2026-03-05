# `*.meta.yml` 用法示例

这个目录演示内容适配器如何使用 sidecar 元数据文件（`*.meta.yml`）覆盖自动推断字段。

## 目录说明

- `input/no-frontmatter.md`：无 front matter，依赖自动推断
- `input/no-frontmatter.md.meta.yml`：覆盖自动推断结果
- `input/with-frontmatter.md`：已有 front matter
- `input/with-frontmatter.md.meta.yml`：覆盖已有 front matter
- `input/docs/target.md`：用于演示 `*.md` 链接重写

## 本地验证

在仓库根目录执行：

```bash
./content-adapter/prepare_content.sh examples/meta-yml/input .runtime/examples-meta-yml content-adapter/content-adapter.toml
```

检查输出：

```bash
sed -n '1,80p' .runtime/examples-meta-yml/posts/no-frontmatter.md
sed -n '1,80p' .runtime/examples-meta-yml/posts/with-frontmatter.md
```

你会看到：

- `title/date/draft/slug` 都会存在
- `*.meta.yml` 中声明的字段会覆盖自动推断或原 front matter
- 指向 `*.md` 的链接会被改写为 Hugo `relref`
