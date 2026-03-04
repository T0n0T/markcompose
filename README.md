# Hugo + Nginx MarkCompose

This directory provides a minimal deployment stack:

- Build blog HTML with `docker.io/hugomods/hugo:dart-sass`
- Serve blog output via Nginx at `/`
- Serve editor static files at `/editor/`
- Serve attachment files at `/attachments/`
- Optional markdown watcher (`markwatch`) for automatic rebuilds

## 1) Start services

### Mode A: custom resources (watcher required, editor optional)

```bash
cd markcompose
./start.sh <markdown_dir> <watcher_path> [attachments_dir] [host_port]
./start.sh <markdown_dir> <editor_static_dir> <watcher_path> [attachments_dir] [host_port]
```

Shortcut with default attachments path `${markdown_dir}/attachments`:

```bash
./start.sh <markdown_dir> <watcher_path> [host_port]
./start.sh <markdown_dir> <editor_static_dir> <watcher_path> [host_port]
```

`watcher_path` can be either a `markwatch` binary path or an extracted directory that contains the binary.
If `editor_static_dir` is omitted, an empty directory is mounted to Nginx `/editor/` and startup output will show that editor is not configured.

### Mode B: one-click default resources (recommended)

```bash
cd markcompose
./start.sh --use-default-resources <markdown_dir> [attachments_dir] [host_port]
```

In `--use-default-resources` mode:

- `markflow-dist.tar.gz` (editor static package) and
  `markwatch-x86_64-unknown-linux-gnu.tar.gz` (watcher package)
  are checked in current project directory first.
- If local package is missing, script auto-downloads from:
  - `https://github.com/T0n0T/markflow/releases/latest/download/markflow-dist.tar.gz`
  - `https://github.com/T0n0T/markwatch/releases/latest/download/markwatch-x86_64-unknown-linux-gnu.tar.gz`
- Packages are extracted to `./.runtime/`.
- `markwatch` starts automatically in background (disable with `--no-watch`).

Examples:

```bash
./start.sh /data/blog/markdown /opt/markwatch/bin/markwatch
./start.sh /data/blog/markdown /data/editor/dist /opt/markwatch/bin/markwatch
./start.sh --use-default-resources /data/blog/markdown
./start.sh --use-default-resources /data/blog/markdown /data/blog/attachments 9090
```

`start.sh` will:

1. Validate input paths
2. Validate `watcher_path` in custom mode, or prepare editor/watcher resources (in default-resources mode)
3. Generate `.env.runtime`
4. Run one Hugo build
5. Start Nginx
6. Start `markwatch` background process (unless `--no-watch`)

## 2) Trigger a single build

```bash
cd markcompose
./build.sh
```

You can also run:

```bash
docker compose --env-file .env.runtime run --rm --no-deps hugo-builder
```

## 3) Stop services

```bash
cd markcompose
./stop.sh
```

Remove named volumes too:

```bash
./stop.sh -v
```

`stop.sh` will stop both docker services and the background `markwatch` process (if started by `start.sh`).

## 4) URL mapping

- `/` -> Hugo build output
- `/editor/` -> editor static files
- `/attachments/` -> attachment files

## 5) Notes

- This stack does not run `hugo server`.
- In default-resources mode, watcher logs are written to `./.markwatch.log`.
- Hugo does not automatically rewrite arbitrary attachment links in Markdown. Keep links aligned with your Nginx path rules (for example, `/attachments/...`).
