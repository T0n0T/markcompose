# Hugo + Nginx MarkCompose

Minimal split-port stack for a Hugo blog and a static editor.

## What this stack does

- Builds blog HTML with `docker.io/hugomods/hugo:dart-sass`
- Serves blog static files on `host_port` (default `8080`)
- Serves editor static files on `editor_port` (default `8081`)
- Serves markdown-managed assets from Hugo output under `/<pic_dir>/` (default `/_assets/`)
- Optionally runs a markdown watcher (`markwatch`) for automatic release builds

## Port mapping

- `http://127.0.0.1:<host_port>/` -> blog static output (`/var/www/blog`)
- `http://127.0.0.1:<editor_port>/` -> editor static files (`/var/www/editor`)
- `http://127.0.0.1:<host_port>/<pic_dir>/...` -> markdown assets from Hugo output (`/var/www/blog/<pic_dir>/...`)

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

1. Local archive in project root
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

`--use-default-resources` is accepted for compatibility, but optional.

## Options

- `--pic-dir <name>`: asset folder name under markdown root (default: `_assets`)
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
./start.sh --pic-dir images /data/blog/markdown
./start.sh --use-custom-watcher "markwatch --some-flag value" /data/blog/markdown
./start.sh --use-custom-editor /data/editor/dist -p 8080 --editor-port 8081 /data/blog/markdown
./start.sh --use-custom-editor /data/editor/dist --use-custom-watcher "markwatch" --pic-dir images -p 8080 --editor-port 8081 /data/blog/markdown
```

## What `start.sh` does

1. Validates paths and ports (`host_port` and `editor_port` must be different)
2. Prepares default resources for parts not customized
3. Writes `.env.runtime`
4. Runs one release build (`build.sh`)
5. Starts `nginx` container
6. Starts `markwatch` in background unless `--no-watch`

## Trigger a single build

```bash
cd markcompose
./build.sh
```

`build.sh` is a release pipeline, not just raw `hugo`:

1. Build to a temporary staging directory
2. Run gate checks (for example generated site has `index.html`)
3. Replace the published `hugo_public` output with clean staged files (removes stale files)

Watcher-triggered builds use the same `build.sh` pipeline.

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

- `.env.runtime`: runtime env used by compose/build commands
- `.runtime/`: extracted default resources
- `.markwatch.pid`: watcher PID (if running)
- `.markwatch.log`: watcher log
- `hugo-reuse/layouts/_markup/`: reusable, theme-agnostic render hooks for path normalization

## Known constraints

- `markcompose` currently supports Linux hosts only.
- This stack does not run `hugo server`.
- `start.sh` rejects paths containing whitespace.
- Default watcher archive auto-selects Linux `amd64`/`arm64`; on other platforms, use `--use-custom-watcher`.
- A freshly bootstrapped `hugo-site` is a bare Hugo skeleton; add theme/layout templates before expecting full page output.
- Markdown image/link paths whose relative path starts with `<pic_dir>/` or `./<pic_dir>/` are rewritten to `/<pic_dir>/...` during Hugo render.
- Absolute URLs, protocol-relative URLs, root-absolute paths (`/foo`), and paths outside `<pic_dir>/` are not rewritten.
- Build/publish is full-site Hugo build each run (not cross-run incremental).
