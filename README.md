# Hugo + Nginx MarkCompose

Minimal split-port stack for a Hugo blog and a static editor.

## What this stack does

- Builds blog HTML with `docker.io/hugomods/hugo:dart-sass`
- Serves blog static files on `HOST_PORT` (default `8080`)
- Serves editor static files on `EDITOR_PORT` (default `8081`)
- Serves markdown-managed assets from Hugo output under `/<ASSETS_DIR>/` (default `/_assets/`)
- Proxies Waline comments API/admin under `/waline/` on the blog port
- Optionally runs a markdown watcher (`markwatch`) for automatic release builds

## Port mapping

- `http://127.0.0.1:<HOST_PORT>/` -> blog static output (`/var/www/blog`)
- `http://127.0.0.1:<EDITOR_PORT>/` -> editor static files (`/var/www/editor`)
- `http://127.0.0.1:<HOST_PORT>/<ASSETS_DIR>/...` -> markdown assets from Hugo output (`/var/www/blog/<ASSETS_DIR>/...`)
- `http://127.0.0.1:<HOST_PORT>/waline/` -> Waline API/admin (`/waline/ui`)

Notes:

- Editor port serves editor static files only; blog pages/assets are on blog port.
- `/editor/` path is not used in split-port mode.

## Requirements

- Docker with `docker compose`
- `bash`
- `realpath`
- `tar` (required when default resources are used)
- `curl` or `wget` (required when default archives need download)

## Quick start

```bash
cd markcompose
./start.sh <markdown_dir>
```

This default mode uses bundled/default resources:

- [editor](https://github.com/T0n0T/markflow): `markflow-dist.tar.gz` 
- [watcher](https://github.com/T0n0T/markwatch): auto-detected by host arch (`markwatch-x86_64-unknown-linux-gnu.tar.gz` or `markwatch-aarch64-unknown-linux-gnu.tar.gz`)

Lookup order:

1. Local archive in `./.runtime/`
2. Otherwise download from GitHub release `latest`
3. Extract to `./.runtime/`

Default URLs:

- `https://github.com/T0n0T/markflow/releases/latest/download/markflow-dist.tar.gz`
- `https://github.com/T0n0T/markwatch/releases/latest/download/markwatch-<target>.tar.gz`

## Start modes

Default resources (same as quick start):

```bash
./start.sh [options] <markdown_dir>
```

Custom watcher only:

```bash
./start.sh --use-custom-watcher <watcher_cmd> <markdown_dir>
```

Custom editor only:

```bash
./start.sh --use-custom-editor <editor_static_dir> <markdown_dir>
```

Custom editor + custom watcher:

```bash
./start.sh --use-custom-editor <editor_static_dir> --use-custom-watcher <watcher_cmd> <markdown_dir>
```

Adapter toggle:

- Enable adaptation by passing `--content-adapter <script_path>` to `start.sh`.
- Disable adaptation by omitting `--content-adapter`.

## Options

- `-a, --assets-dir <dir>`: asset folder name under markdown root (default: `_assets`)
- `--content-adapter <script>`: adapter script path to transform markdown before Hugo build (default: disabled)
- `-p, --host-port <port>`: blog host port (default: `8080`)
- `--editor-port <port>`: editor host port (default: `8081`)
- `--no-watch`: do not start watcher
- `--debounce-ms <num>`: default watcher debounce ms (default: `800`)
- `--reconcile-sec <num>`: default watcher reconcile sec (default: `600`)
- `--watch-log-level <level>`: default watcher log level (default: `info`)

Watcher notes:

- In custom watcher mode, `--debounce-ms`, `--reconcile-sec`, and `--watch-log-level` are ignored.
- Use a single foreground command for `<watcher_cmd>` (for example `"markwatch"`). Avoid `&&`, `|`, and trailing `&`, otherwise `stop.sh` may not clean up all child processes.

## Examples

```bash
./start.sh /data/blog/markdown
./start.sh --content-adapter content-adapter/prepare_content.sh /data/blog/markdown
./start.sh --assets-dir images /data/blog/markdown
./start.sh --use-custom-watcher "markwatch --some-flag value" /data/blog/markdown
./start.sh --use-custom-editor /data/editor/dist -p 8080 --editor-port 8081 /data/blog/markdown
./start.sh --use-custom-editor /data/editor/dist --use-custom-watcher "markwatch" --assets-dir images -p 8080 --editor-port 8081 /data/blog/markdown
```

## `MARKDOWN_DIR` layout

Current adapter rules assume the markdown workspace (`MARKDOWN_DIR`) is organized like this:

```text
<markdown_dir>/
├── _assets/                      # default ASSETS_DIR; served as /_assets/...
│   └── ...
├── 2026-03-01-hello.md           # root-level markdown (mapped to default section)
├── 2026-03-01-hello.md.meta.yml  # optional sidecar override for the markdown file
├── notes/
│   ├── index.md
│   ├── deep-dive.md
│   └── deep-dive.md.meta.yml
└── projects/
    └── alpha.md
```

Notes:

- `--assets-dir <dir>` controls the asset folder name (default `_assets`).
- Markdown files under root are mapped to `default_section` (default: `posts`).
- Markdown files in subdirectories keep their relative paths (for example `notes/a.md` stays under `notes/`).
- Sidecar files supported by default: `*.meta.yaml` and `*.meta.yml`.
- Sidecar fields override inferred/front matter fields.
- `*.md` links are rewritten to Hugo internal links (`relref`) when target files exist.
- Directories listed in `content-adapter/content-adapter.toml` `ignore_dirs` (default `.git`, `.runtime`) are skipped.

## What `start.sh` does

1. Validates paths and ports (`HOST_PORT` and `EDITOR_PORT` must be different)
2. Prepares default resources for parts not customized
3. Writes `.env.runtime`
4. Runs one release build (`build.sh`)
5. Starts `waline` + `nginx` containers
6. Starts `markwatch` in background unless `--no-watch`

## Waline configuration

Set these in `.env` (recommended) before `start.sh`:

- `WALINE_JWT_TOKEN`: required in production; use a long random secret
- `WALINE_SITE_NAME`: optional site name shown by Waline (default `Blog Comments`)
- `WALINE_SITE_URL`: optional canonical site URL (default `http://127.0.0.1:8080`)
- `WALINE_SERVER_URL`: optional forced public base URL for Waline API/admin (recommended when using Cloudflare Tunnel)

Cloudflare Tunnel note:

- Keep `Host` as your public domain
- Keep `X-Forwarded-Proto: https` so Waline admin renders `https://.../api/` instead of `http://.../api/`

After startup, initialize admin at `http://127.0.0.1:<HOST_PORT>/waline/ui`.

If Waline logs show `no such table: wl_Users` or `wl_Comment`, initialize SQLite from the official seed DB:

```bash
curl -fL -o /tmp/waline.sqlite https://raw.githubusercontent.com/walinejs/waline/main/assets/waline.sqlite
cat /tmp/waline.sqlite | docker compose --env-file .env.runtime exec -T waline sh -lc 'cat > /app/data/waline.sqlite'
docker compose --env-file .env.runtime restart waline nginx
```

## Trigger a single build

```bash
cd markcompose
./build.sh
```

`build.sh` is a release pipeline, not just raw `hugo`:

1. If a content adapter is configured (for example via `start.sh --content-adapter ...`), adapt plain Markdown into Hugo-ready content under `.runtime/content-adapted` (does not modify the originals)
2. Build to a temporary staging directory
3. Run gate checks (for example generated site has `index.html`)
4. Replace the published `hugo_public` output with clean staged files (removes stale files)

Watcher-triggered builds use the same `build.sh` pipeline.

Content adapter notes:

- Adapter entrypoint: `content-adapter/prepare_content.sh`
- Config: `content-adapter/content-adapter.toml`
- Sidecar meta override: `foo.md.meta.yaml` (or `.meta.yml`) next to the markdown file, to override inferred front matter fields
- Sidecar example: `examples/meta-yml/`
- Enable adapter: run `./start.sh --content-adapter content-adapter/prepare_content.sh <markdown_dir>`
- Disable adapter: rerun `start.sh` without `--content-adapter`

Bootstrap behavior:

- If `./hugo-site` does not exist, `build.sh` will run `hugo new site hugo-site` in the Hugo Docker image.
- After bootstrap, reusable render hooks are copied from `./hugo-reuse/layouts/_markup/` into `./hugo-site/layouts/_markup/`.

## Stop services

```bash
cd markcompose
./stop.sh
```

Remove named volumes too:

```bash
./stop.sh -v
```

`stop.sh` runs `docker compose down` (or `down --volumes`) and then stops the background `markwatch` process if a PID file exists.

## Runtime files

- `.env` (optional): baseline env. If present, `start.sh` uses it as the base and then overwrites runtime-managed keys into `.env.runtime`
- `.env.runtime`: runtime env used by compose/build commands
- `docker-compose.yml` maps `ASSETS_DIR` to `HUGO_ASSETS_DIR` for Hugo render hooks
- `hugo-site/config/_default/hugo.toml`: Hugo main config (LoveIt/search/comment settings)
- `.runtime/`: downloaded default archives and extracted default resources
- `.markwatch.pid`: watcher PID (if running)
- `.markwatch.log`: watcher log
- `hugo-reuse/layouts/_markup/`: reusable, theme-agnostic render hooks for path normalization

## Known constraints

- `markcompose` currently supports Linux hosts only.
- This stack does not run `hugo server`.
- `start.sh` rejects paths containing whitespace.
- Default watcher archive auto-selects Linux `amd64`/`arm64`; on other platforms, use `--use-custom-watcher`.
- A freshly bootstrapped `hugo-site` is a bare Hugo skeleton; add theme/layout templates before expecting full page output.
- Markdown image/link paths whose relative path starts with `<ASSETS_DIR>/` or `./<ASSETS_DIR>/` are rewritten to `/<ASSETS_DIR>/...` during Hugo render.
- Absolute URLs, protocol-relative URLs, root-absolute paths (`/foo`), and paths outside `<ASSETS_DIR>/` are not rewritten.
- Build/publish is full-site Hugo build each run (not cross-run incremental).
