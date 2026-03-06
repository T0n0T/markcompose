# Repository Guidelines

## Project Structure & Module Organization
- `markcompose.sh` is the only top-level user entrypoint; it dispatches `init-site`, `start`, `build`, and `stop`.
- `scripts/` contains command implementations; shared shell helpers live in `scripts/lib/`.
- `adapter/` contains optional Markdown adaptation logic: `prepare_content.sh`, `content_adapter.py`, and `content-adapter.toml`.
- `hugo-site/` is the Hugo project, theme config, and static site source.
- `hugo-reuse/layouts/` stores reusable Hugo layouts copied into `hugo-site/layouts/` during builds.
- `nginx/` contains reverse-proxy config; `docs/` contains operational notes; `examples/` and `markdown_test/` provide sample content.
- Runtime artifacts are written to `.runtime/`, `.env.runtime`, and `.markwatch.*`; do not commit generated files.

## Build, Test, and Development Commands
- `./markcompose.sh init-site`: create a fresh `hugo-site/` skeleton with the Hugo Docker image.
- `./markcompose.sh start <markdown_dir>`: validate inputs, build once, and start Nginx/Waline.
- `./markcompose.sh start --content-adapter adapter/prepare_content.sh <markdown_dir>`: same as above, with Markdown adaptation enabled.
- `./markcompose.sh build [env_file]`: run the release build pipeline and publish into the Docker volume.
- `./markcompose.sh stop [-v]`: stop services; `-v` also removes named volumes.
- Validation commands used in this repo:
  - `bash -n markcompose.sh scripts/*.sh scripts/lib/*.sh adapter/prepare_content.sh`
  - `shellcheck markcompose.sh scripts/*.sh scripts/lib/*.sh adapter/prepare_content.sh`
  - `python3 -m py_compile adapter/content_adapter.py`

## Coding Style & Naming Conventions
- Shell scripts use `bash`, `set -euo pipefail`, 2-space indentation, and `mc::namespace::function` helper names.
- Prefer small modules over large inline scripts; keep adapter code isolated from runtime command logic.
- Python follows standard library-first style, snake_case names, and concise functions.
- Keep CLI output short, phase-based, and readable.

## Testing Guidelines
- There is no formal unit test suite yet; use smoke validation instead.
- For adapter changes, run `./adapter/prepare_content.sh markdown_test .runtime/content-adapted-test`.
- For end-to-end checks, use an isolated Compose project name, e.g. `MARKCOMPOSE_COMPOSE_PROJECT_NAME=markcompose_validate ./markcompose.sh start ...`.

## Commit & Pull Request Guidelines
- Follow the existing history style: `feat: ...`, `fix: ...`, `chore: ...`, or concise refactor summaries.
- Keep commits focused by concern (CLI, adapter, docs, config).
- PRs should include: purpose, key paths changed, validation steps run, and screenshots/log snippets for UI or proxy-related changes.

## Security & Configuration Tips
- Store stable settings in `.env`; let `start` regenerate `.env.runtime`.
- Set a real `WALINE_JWT_TOKEN` outside local demos.
- Use `./markcompose.sh stop -v` carefully: it deletes Waline data.
