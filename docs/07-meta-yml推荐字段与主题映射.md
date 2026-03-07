# 07 `meta.yml` 推荐字段与主题映射

## 1. 这份文档解决什么问题

`*.meta.yml` / `*.meta.yaml` 是内容适配器的 sidecar 元数据文件。

它的作用不是“发明一套新字段”，而是把字段覆盖到最终 front matter 中。真正决定“字段有没有页面效果”的，是两层：

1. Hugo front matter 本身是否识别
2. 当前主题与项目 layouts 是否实际读取

所以：

- 想知道 **能不能写**：看 adapter
- 想知道 **写了有没有展示效果**：看主题和当前 layouts

本文档基于当前仓库实际生效的模板整理，目标是给出“推荐写法”，而不是列一个看起来很全、实际没几项会生效的清单。

## 2. sidecar 合并规则

合并优先级（高 -> 低）：

1. sidecar（`*.meta.yaml` / `*.meta.yml`）
2. 原文件 front matter（YAML/TOML）
3. 自动推断（`title/date/draft/slug`）

其中：

- `title/date/draft/slug` 最终一定会存在
- sidecar 可以覆盖自动推断和原 front matter
- sidecar 不限于基础字段，任意顶层 YAML key 都可以写入最终 front matter

### 2.1 一个关键边界：当前是“浅合并”

当前 adapter 逻辑等价于顶层 `dict.update()`。

这意味着：

- 顶层字段会被覆盖
- **嵌套对象不会深合并**

示例：

```yaml
# 原 front matter
comment:
  enable: true
  waline:
    enable: true
    serverURL: /waline
```

如果 sidecar 写：

```yaml
comment:
  enable: false
```

最终结果会是：

```yaml
comment:
  enable: false
```

而不是“只改一个子字段、保留 waline 其他配置”。

因此对这些对象字段：

- `toc`
- `math`
- `share`
- `comment`
- `mapbox`
- `library`
- `seo`

建议要么：

- 直接用布尔值做简单开关
- 要么写完整对象，不要只补半截

## 3. 当前项目里推荐关注的字段

下面的字段分成 4 类：

- 核心必备：建议大多数文章都具备
- 展示增强：提升页面信息密度和视觉效果
- 功能开关：按文章类型开启
- 高级对象：适合有明确需求时再写

## 4. 核心必备字段

### 4.1 `title`

- 用途：文章标题
- 来源：Hugo 原生 + 主题直接读取 `.Title`
- 建议：始终显式写入；不要长期依赖自动推断

### 4.2 `date`

- 用途：发布时间
- 出现场景：列表页、详情页、SEO、RSS
- 建议：需要稳定发布时间时显式写入；不要完全依赖 mtime

### 4.3 `draft`

- 用途：草稿开关
- 来源：Hugo 原生
- 建议：团队协作时显式写入，避免默认值误伤发布

### 4.4 `slug`

- 用途：文章 URL slug
- 来源：Hugo 原生
- 建议：对外链或 SEO 敏感文章建议固定写入

### 4.5 `description`

- 用途：摘要 / `<meta name="Description">` / SEO / 分享描述
- 当前项目状态：主题模板会直接读取
- 建议：推荐写一行短摘要，别让搜索结果和分享卡片裸奔

### 4.6 `tags`

- 用途：标签页、搜索索引、SEO、分享
- 当前项目状态：主题模板会直接读取
- 建议：技术站点建议保持一致的标签体系

### 4.7 `categories`

- 用途：分类页、文章元信息展示、搜索索引
- 当前项目状态：主题模板会直接读取
- 建议：分类控制在较少层级，别把分类写成树状族谱

## 5. 展示增强字段

### 5.1 `subtitle`

- 用途：文章副标题
- 当前项目状态：详情页显示
- 建议：长文、系列文、翻译文可以用；短文没必要硬凑

### 5.2 `author`

- 用途：作者名
- 当前项目状态：摘要页、详情页、SEO 会读取
- 建议：多人协作站点应显式写入

### 5.3 `authorlink`

- 用途：作者链接
- 当前项目状态：摘要页、详情页会读取
- 建议：有作者页、主页或社交主页时再写

### 5.4 `featuredimage`

- 用途：文章封面图
- 当前项目状态：详情页、摘要页、RSS、部分分享组件会读取
- 建议：封面图型内容推荐写；纯笔记可省略

### 5.5 `featuredimagepreview`

- 用途：摘要列表预览图
- 当前项目状态：摘要页优先读取；缺失时回退到 `featuredimage`
- 建议：需要列表页用裁切图时再写

### 5.6 `license`

- 用途：文章页底部许可说明
- 当前项目状态：详情页 footer 显示
- 建议：转载规则明确的内容可以写

### 5.7 `linktomarkdown`

- 用途：显示“查看 Markdown 原文”入口
- 当前项目状态：详情页 footer 读取
- 建议：如果站点开启 Markdown 输出格式，可保留；否则别硬开摆设

### 5.8 `prev` / `next`

- 用途：手动指定上一篇 / 下一篇
- 当前项目状态：详情页 footer 读取；不写时使用 section 内默认顺序
- 建议：系列内容可手动控制，普通文章不必强行干预

## 6. 功能开关字段

### 6.1 `toc`

- 用途：目录开关与细项配置
- 支持写法：
  - `toc: true`
  - `toc: false`
  - 对象写法（如 `enable/keepStatic/auto`）
- 建议：技术长文推荐开，短文没必要挂一大坨目录装忙

### 6.2 `math`

- 用途：KaTeX 数学公式开关与细项配置
- 支持写法：
  - `math: true`
  - `math: false`
  - 对象写法（如 `enable/copyTex/mhchem`）
- 建议：只在真的有公式时开启，别让页面平白多背资源成本

### 6.3 `lightgallery`

- 用途：图片画廊支持
- 当前项目状态：资源注入层会读取
- 建议：图集、摄影、步骤图文时开启

### 6.4 `twemoji`

- 用途：emoji 渲染增强
- 建议：按需使用，通常不是高优先级

### 6.5 `ruby`

- 用途：ruby 扩展语法
- 建议：日文注音等内容按需开启；普通文章无需在意

### 6.6 `fraction`

- 用途：分数扩展语法
- 建议：数学或教学内容按需开启

### 6.7 `fontawesome`

- 用途：Font Awesome 扩展语法
- 建议：需要特定图标语法时开启

### 6.8 `share`

- 用途：文章页分享开关与平台配置
- 支持写法：
  - `share: true` / `false`
  - 完整对象
- 注意：如果要自定义平台开关，建议写完整对象

### 6.9 `comment`

- 用途：评论系统开关或页面级评论配置
- 支持写法：
  - `comment: true`：启用站点默认评论配置
  - `comment: false`：当前页面禁用评论
  - `comment: {...}`：提供页面级评论配置
- 注意：对象写法同样受“浅合并”影响，建议写完整对象

### 6.10 `rssfulltext`

- 用途：RSS 输出全文
- 当前项目状态：RSS 模板读取
- 建议：订阅友好优先时开启；担心抓取或摘要过长时关闭

### 6.11 `hiddenfromhomepage`

- 用途：首页列表隐藏
- 当前项目状态：主题首页列表会过滤
- 建议：站务页、说明页、私有笔记镜像可用

### 6.12 `hiddenfromsearch`

- 用途：站内搜索索引隐藏
- 当前项目状态：搜索索引生成会过滤
- 建议：噪音页、低价值页、内部说明页可用

## 7. 高级对象字段

### 7.1 `seo`

当前主题模板会读取至少以下内容：

- `seo.images`
- `seo.publisher`

适合：

- 需要指定社交卡片图片
- 需要覆盖结构化数据中的 publisher 信息

### 7.2 `mapbox`

当前资源层会读取 `mapbox.accessToken` 等配置。

适合：

- 页面内容里确实使用了 Mapbox 相关 shortcode 或交互地图

### 7.3 `library`

当前资源层会读取：

- `library.css`
- `library.js`

适合：

- 单页注入额外样式 / 脚本

注意：

- 这是进阶用法
- 建议保持可审计，不要让页面级脚本到处乱飞

## 8. 一个实用判断：哪些字段是真正高性价比

如果只追求“够用、稳定、少踩坑”，建议优先写：

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

这套字段已经覆盖了：

- 标题与 URL 稳定性
- 列表页与详情页信息展示
- SEO 与分享的基础信息
- 目录与评论开关

对大多数文章来说，这一版比“塞满一堆几乎用不上的字段”更省心。

## 9. 推荐模板：完整但不过度

下面这份更适合作为团队示例模板：

```yaml
title: 文章标题
date: 2026-03-07T12:00:00Z
draft: false
slug: article-slug

description: 一句话描述这篇文章，给 SEO、摘要、分享兜底。
tags:
  - Hugo
  - Markdown
categories:
  - 技术

author: Your Name
authorlink: https://example.com/about
subtitle: 这里可以放副标题

featuredimage: /images/article-cover.jpg
featuredimagepreview: /images/article-cover-preview.jpg

license: CC BY-NC-SA 4.0
linktomarkdown: true
rssfulltext: false

hiddenfromhomepage: false
hiddenfromsearch: false

toc:
  enable: true
  keepStatic: false
  auto: true

math:
  enable: false
  copyTex: true
  mhchem: true

lightgallery: false
twemoji: false
ruby: true
fraction: true
fontawesome: true

share:
  enable: true
  X: true
  Threads: true
  Facebook: true
  Linkedin: false
  Whatsapp: false
  Pinterest: false
  Tumblr: false
  HackerNews: true
  Reddit: false
  VK: false
  Buffer: false
  Xing: false
  Line: true
  Weibo: true
  Telegram: true

comment:
  enable: true
  waline:
    enable: true
    serverURL: /waline
    emoji:
      - https://unpkg.com/@waline/emojis@1.1.0/weibo

seo:
  images:
    - /images/article-cover.jpg
  publisher:
    name: Your Name
```

## 10. 命名建议

当前项目的主题模板大量使用小写键访问页面参数，例如：

- `featuredimage`
- `featuredimagepreview`
- `authorlink`
- `linktomarkdown`
- `hiddenfromhomepage`
- `hiddenfromsearch`

因此，团队约定建议：

- `meta.yml` 优先使用小写 key
- 不要在同一仓库里混用多种大小写风格

## 11. 不推荐的写法

### 11.1 把主题会直接读取的字段塞进 `params.*`

例如当前主题展示作者时，优先读取的是：

- `author`
- `authorlink`

而不是：

```yaml
params:
  author: someone
```

`params.author` 当然可以存进去，但当前模板不一定直接用。不要把“能写”误当“会显示”。

### 11.2 只写半截对象并期待深合并

例如：

```yaml
comment:
  enable: true
```

如果原 front matter 里还有更完整的 `comment.waline` 配置，sidecar 顶层覆盖后很可能把那部分整个冲掉。

### 11.3 长期依赖自动推断基础字段

自动推断是兜底，不是最佳实践。对正式内容，建议显式写：

- `title`
- `date`
- `draft`
- `slug`

## 12. 结论

`meta.yml` 没有严格字段白名单，但“最完整、最有用”的字段集合必须结合当前主题与 layouts 来看。

在当前仓库下，最值得优先维护的是：

- `title/date/draft/slug`
- `description/tags/categories`
- `author/subtitle/featuredimage`
- `toc/comment`

能省的配置就省，能直接决定页面效果的字段优先写。别跟低性价比元数据死磕。
