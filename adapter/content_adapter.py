from __future__ import annotations

import os
import re
import sys
import shutil
import posixpath
import datetime as datetime_lib
import urllib.parse
from dataclasses import dataclass

import tomllib
import yaml


def die(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(1)


def info(msg: str) -> None:
    print(f"→ {msg}")


def kv(label: str, value: object) -> None:
    print(f"  {label:<12} {value}")


@dataclass
class AdaptStats:
    files_written: int = 0
    sidecars_applied: int = 0
    stripped_h1: int = 0
    rewritten_link_docs: int = 0


def load_toml(path: str) -> dict:
    try:
        with open(path, "rb") as file_handle:
            return tomllib.load(file_handle) or {}
    except FileNotFoundError:
        die(f"Config not found: {path}")
    except Exception as e:
        die(f"Failed to read config {path}: {e}")


def ensure_clean_dir(path: str) -> None:
    if os.path.exists(path):
        shutil.rmtree(path)
    os.makedirs(path, exist_ok=True)


def to_posix(relpath: str) -> str:
    return relpath.replace(os.sep, "/")


def list_markdown_files(input_dir: str, *, pic_dir: str, ignore_dirs: set[str]) -> list[str]:
    markdown_paths: list[str] = []
    for root, dirs, files in os.walk(input_dir, topdown=True):
        # Prune ignored dirs.
        pruned_dirs: list[str] = []
        for dir_name in dirs:
            if dir_name == pic_dir:
                continue
            if dir_name in ignore_dirs:
                continue
            pruned_dirs.append(dir_name)
        dirs[:] = pruned_dirs

        for file_name in files:
            if not file_name.lower().endswith(".md"):
                continue
            source_path = os.path.join(root, file_name)
            # Extra guard: skip anything under the asset dir.
            source_rel_path = os.path.relpath(source_path, input_dir)
            source_rel_path_posix = to_posix(source_rel_path)
            if source_rel_path_posix.startswith(f"{pic_dir}/"):
                continue
            markdown_paths.append(source_path)
    markdown_paths.sort()
    return markdown_paths


def split_front_matter(text: str) -> tuple[str | None, dict, str]:
    # Supports YAML (---) and TOML (+++). Returns (kind, data, body).
    if text.startswith("---\n") or text.startswith("---\r\n"):
        delim = "---"
        kind = "yaml"
    elif text.startswith("+++\n") or text.startswith("+++\r\n"):
        delim = "+++"
        kind = "toml"
    else:
        return None, {}, text

    lines = text.splitlines(True)
    if not lines or lines[0].strip() != delim:
        return None, {}, text

    front_matter_end_index = None
    for line_index in range(1, len(lines)):
        if lines[line_index].strip() == delim:
            front_matter_end_index = line_index
            break
    if front_matter_end_index is None:
        return None, {}, text

    front_matter_text = "".join(lines[1:front_matter_end_index])
    body = "".join(lines[front_matter_end_index + 1 :])
    try:
        if kind == "yaml":
            data = yaml.safe_load(front_matter_text) or {}
        else:
            data = tomllib.loads(front_matter_text) or {}
        if not isinstance(data, dict):
            data = {}
        return kind, data, body
    except Exception:
        # Be conservative: if parsing fails, treat file as "no front matter".
        return None, {}, text


FENCE_RE = re.compile(r"^(\s*)(```+|~~~+)")
H1_RE = re.compile(r"^#\s+(.+?)\s*$")


def find_first_h1(body: str) -> tuple[str | None, int | None]:
    lines = body.splitlines(True)
    in_fence = False
    fence_char = ""
    fence_len = 0

    for line_index, line in enumerate(lines):
        fence_match = FENCE_RE.match(line.rstrip("\r\n"))
        if fence_match:
            marker = fence_match.group(2)
            if not in_fence:
                in_fence = True
                fence_char = marker[0]
                fence_len = len(marker)
            else:
                if marker[0] == fence_char and len(marker) >= fence_len:
                    in_fence = False
            continue

        if in_fence:
            continue

        h1_match = H1_RE.match(line.rstrip("\r\n"))
        if h1_match:
            title = h1_match.group(1).strip()
            title = re.sub(r"\s+#+\s*$", "", title).strip()
            return title, line_index

    return None, None


def strip_first_h1_if_leading(body: str, h1_idx: int) -> str:
    lines = body.splitlines(True)
    first_nonblank = None
    for line_index, line in enumerate(lines):
        if line.strip() != "":
            first_nonblank = line_index
            break
    if first_nonblank is None or first_nonblank != h1_idx:
        return body

    del lines[h1_idx]
    if h1_idx < len(lines) and lines[h1_idx].strip() == "":
        del lines[h1_idx]
    return "".join(lines)


def infer_title(body: str, filename_stem: str) -> tuple[str, int | None]:
    title, idx = find_first_h1(body)
    if title:
        return title, idx
    # Fall back to filename (strip leading date prefix if present).
    date_prefix_match = re.match(r"^\d{4}[-_]\d{2}[-_]\d{2}[-_ ]+(.*)$", filename_stem)
    if date_prefix_match:
        filename_stem = date_prefix_match.group(1) or filename_stem
    return filename_stem, None


def infer_date(src_path: str, filename_stem: str) -> str:
    # Prefer date prefix in filename for stability, else fall back to mtime (UTC).
    date_prefix_match = re.match(r"^(?P<y>\d{4})[-_](?P<m>\d{2})[-_](?P<d>\d{2})(?:$|[-_ ].*)", filename_stem)
    if date_prefix_match:
        year, month, day = int(date_prefix_match.group("y")), int(date_prefix_match.group("m")), int(date_prefix_match.group("d"))
        date_value = datetime_lib.datetime(year, month, day, 0, 0, 0, tzinfo=datetime_lib.timezone.utc)
        return date_value.strftime("%Y-%m-%dT%H:%M:%SZ")

    mtime_timestamp = os.path.getmtime(src_path)
    date_value = datetime_lib.datetime.fromtimestamp(mtime_timestamp, tz=datetime_lib.timezone.utc)
    # Use seconds precision for deterministic output.
    date_value = date_value.replace(microsecond=0)
    return date_value.strftime("%Y-%m-%dT%H:%M:%SZ")


SLUG_SAFE_RE = re.compile(r"[^a-z0-9\-]+")


def slugify(stem: str) -> str:
    raw_stem = stem.strip()
    date_prefix_match = re.match(r"^\d{4}[-_]\d{2}[-_]\d{2}[-_ ]+(.*)$", raw_stem)
    if date_prefix_match:
        raw_stem = date_prefix_match.group(1) or raw_stem
    ascii_slug = raw_stem.lower().replace("_", "-").replace(" ", "-")
    ascii_slug = SLUG_SAFE_RE.sub("-", ascii_slug)
    ascii_slug = re.sub(r"-{2,}", "-", ascii_slug).strip("-")
    if ascii_slug:
        return ascii_slug
    # Fallback: keep unicode (Hugo supports it) but normalize whitespace.
    unicode_slug = re.sub(r"\s+", "-", raw_stem)
    unicode_slug = re.sub(r"-{2,}", "-", unicode_slug).strip("-")
    return unicode_slug or "post"


REF_DEF_RE = re.compile(r"^(\[([^\]]+)\]:\s*)(<[^>]+>|\S+)(.*)$")


def resolve_md_target(
    dest: str,
    *,
    current_src_rel_posix: str,
    in_to_out_posix: dict[str, str],
) -> str | None:
    if "{{<" in dest or "{{%" in dest:
        return None
    if dest.startswith("//"):
        return None
    if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", dest):
        return None
    if dest.startswith("#") or dest.startswith("/"):
        return None

    parsed_url = urllib.parse.urlsplit(dest)
    url_path = parsed_url.path
    if not url_path.lower().endswith(".md"):
        return None

    current_source_dir = posixpath.dirname(current_src_rel_posix)
    resolved_target_path = posixpath.normpath(posixpath.join(current_source_dir, url_path))
    if resolved_target_path.startswith("../") or resolved_target_path == "..":
        return None

    target_output_path = in_to_out_posix.get(resolved_target_path)
    if not target_output_path:
        return None

    relref_target = f'{{{{< relref "{target_output_path}" >}}}}'
    if parsed_url.query:
        relref_target += "?" + parsed_url.query
    if parsed_url.fragment:
        relref_target += "#" + parsed_url.fragment
    return relref_target


def rewrite_md_links_in_body(body: str, *, current_src_rel_posix: str, in_to_out_posix: dict[str, str]) -> str:
    out_lines: list[str] = []
    lines = body.splitlines(True)

    in_fence = False
    fence_char = ""
    fence_len = 0

    for line in lines:
        fence_match = FENCE_RE.match(line.rstrip("\r\n"))
        if fence_match:
            marker = fence_match.group(2)
            if not in_fence:
                in_fence = True
                fence_char = marker[0]
                fence_len = len(marker)
            else:
                if marker[0] == fence_char and len(marker) >= fence_len:
                    in_fence = False
            out_lines.append(line)
            continue

        if in_fence:
            out_lines.append(line)
            continue

        # Reference link definitions: [id]: foo.md "title"
        ref_definition_match = REF_DEF_RE.match(line)
        if ref_definition_match:
            prefix, dest_raw, rest = ref_definition_match.group(1), ref_definition_match.group(3), ref_definition_match.group(4)
            dest = dest_raw[1:-1] if dest_raw.startswith("<") and dest_raw.endswith(">") else dest_raw
            new_dest = resolve_md_target(dest, current_src_rel_posix=current_src_rel_posix, in_to_out_posix=in_to_out_posix)
            if new_dest:
                out_lines.append(prefix + new_dest + rest)
            else:
                out_lines.append(line)
            continue

        # Inline links: [text](dest ...)
        out_lines.append(rewrite_inline_links(line, current_src_rel_posix=current_src_rel_posix, in_to_out_posix=in_to_out_posix))

    return "".join(out_lines)


def split_dest_and_rest(paren_content: str) -> tuple[str, str, str]:
    # Returns (leading_ws, dest, rest). `rest` includes original spacing/title.
    content = paren_content
    trimmed_content = content.lstrip()
    leading_ws = content[: len(content) - len(trimmed_content)]
    if not trimmed_content:
        return leading_ws, "", ""

    if trimmed_content.startswith("<") and ">" in trimmed_content:
        closing_bracket_index = trimmed_content.find(">")
        dest = trimmed_content[1:closing_bracket_index]
        rest = trimmed_content[closing_bracket_index + 1 :]
        return leading_ws, dest, rest

    first_space_match = re.search(r"\s", trimmed_content)
    if not first_space_match:
        return leading_ws, trimmed_content, ""
    first_space_index = first_space_match.start()
    dest = trimmed_content[:first_space_index]
    rest = trimmed_content[first_space_index:]
    return leading_ws, dest, rest


def rewrite_inline_links(line: str, *, current_src_rel_posix: str, in_to_out_posix: dict[str, str]) -> str:
    rewritten_segments: list[str] = []
    cursor = 0
    line_length = len(line)

    while cursor < line_length:
        link_start = line.find("[", cursor)
        if link_start == -1:
            rewritten_segments.append(line[cursor:])
            break

        # Copy up to '['.
        rewritten_segments.append(line[cursor:link_start])

        # Skip images: ![alt](...)
        if link_start > 0 and line[link_start - 1] == "!":
            rewritten_segments.append("[")
            cursor = link_start + 1
            continue

        link_text_end = line.find("]", link_start + 1)
        if link_text_end == -1 or link_text_end + 1 >= line_length or line[link_text_end + 1] != "(":
            rewritten_segments.append(line[link_start : link_text_end + 1 if link_text_end != -1 else link_start + 1])
            cursor = (link_text_end + 1) if link_text_end != -1 else (link_start + 1)
            continue

        # Find matching ')', allowing nested parentheses.
        scan_index = link_text_end + 2
        depth = 1
        while scan_index < line_length:
            ch = line[scan_index]
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    break
            scan_index += 1
        if depth != 0:
            # Unbalanced, leave as-is.
            rewritten_segments.append(line[link_start:])
            break

        paren_content = line[link_text_end + 2 : scan_index]
        lead_ws, dest, rest = split_dest_and_rest(paren_content)
        new_dest = resolve_md_target(dest, current_src_rel_posix=current_src_rel_posix, in_to_out_posix=in_to_out_posix)
        if new_dest:
            rewritten_segments.append(line[link_start : link_text_end + 2] + lead_ws + new_dest + rest + ")")
        else:
            rewritten_segments.append(line[link_start : scan_index + 1])
        cursor = scan_index + 1

    return "".join(rewritten_segments)


def load_sidecar(src_path: str, sidecar_exts: list[str]) -> dict:
    for sidecar_ext in sidecar_exts:
        sidecar_path = src_path + sidecar_ext
        if not os.path.exists(sidecar_path):
            continue
        try:
            with open(sidecar_path, "r", encoding="utf-8") as file_handle:
                data = yaml.safe_load(file_handle) or {}
            if not isinstance(data, dict):
                die(f"Sidecar meta must be a YAML mapping: {sidecar_path}")
            return data
        except Exception as e:
            die(f"Failed to read sidecar meta {sidecar_path}: {e}")
    return {}


def dump_front_matter_yaml(data: dict) -> str:
    # Stable key ordering: put common keys first, then rest sorted.
    preferred_keys = ["title", "date", "draft", "slug"]
    ordered_data: dict = {}
    for key in preferred_keys:
        if key in data:
            ordered_data[key] = data[key]
    for key in sorted(data.keys()):
        if key in ordered_data:
            continue
        ordered_data[key] = data[key]
    dumped = yaml.safe_dump(ordered_data, sort_keys=False, allow_unicode=True).strip()
    return dumped + ("\n" if dumped else "")


def main() -> None:
    if len(sys.argv) != 4:
        die("Expected args: <input_dir> <output_dir> <config_toml>")

    input_dir = os.path.abspath(sys.argv[1])
    output_dir = os.path.abspath(sys.argv[2])
    config_path = os.path.abspath(sys.argv[3])

    config = load_toml(config_path)
    default_section = str(config.get("default_section", "posts") or "").strip()
    strip_first_h1 = bool(config.get("strip_first_h1", True))
    default_draft = bool(config.get("default_draft", False))
    rewrite_md_links = bool(config.get("rewrite_md_links", True))
    sidecar_exts = config.get("sidecar_exts", [".meta.yaml", ".meta.yml"])
    if not isinstance(sidecar_exts, list) or not all(isinstance(x, str) for x in sidecar_exts):
        die("sidecar_exts must be an array of strings in adapter/content-adapter.toml")

    ignore_dirs = set(config.get("ignore_dirs", [".git", ".runtime"]))
    if not all(isinstance(x, str) for x in ignore_dirs):
        die("ignore_dirs must be an array of strings in adapter/content-adapter.toml")

    pic_dir = os.environ.get("ASSETS_DIR", "_assets").strip() or "_assets"

    if not os.path.isdir(input_dir):
        die(f"Input dir not found: {input_dir}")

    info("Content adapter")
    kv("Input", input_dir)
    kv("Output", output_dir)
    kv("Config", config_path)
    kv("Assets dir", pic_dir)

    ensure_clean_dir(output_dir)

    source_markdown_files = list_markdown_files(input_dir, pic_dir=pic_dir, ignore_dirs=ignore_dirs)
    stats = AdaptStats()

    # Build a mapping from input relpath -> output relpath (posix) for link rewriting.
    in_to_out_posix: dict[str, str] = {}
    for source_path in source_markdown_files:
        source_rel_path = to_posix(os.path.relpath(source_path, input_dir))
        source_rel_dir = posixpath.dirname(source_rel_path)
        source_base_name = posixpath.basename(source_rel_path)
        if source_rel_dir == "":
            output_rel_path = posixpath.join(default_section, source_base_name) if default_section else source_base_name
        else:
            output_rel_path = source_rel_path
        in_to_out_posix[source_rel_path] = output_rel_path

    for source_path in source_markdown_files:
        source_rel_path = to_posix(os.path.relpath(source_path, input_dir))
        output_rel_path = in_to_out_posix[source_rel_path]
        output_path = os.path.join(output_dir, output_rel_path.replace("/", os.sep))
        os.makedirs(os.path.dirname(output_path), exist_ok=True)

        with open(source_path, "r", encoding="utf-8") as file_handle:
            source_text = file_handle.read()

        _kind, front_matter_data, body = split_front_matter(source_text)
        sidecar_data = load_sidecar(source_path, sidecar_exts=sidecar_exts)
        if sidecar_data:
            stats.sidecars_applied += 1

        source_stem = os.path.splitext(os.path.basename(source_path))[0]
        inferred_title, h1_idx = infer_title(body, source_stem)
        inferred_date = infer_date(source_path, source_stem)
        inferred_slug = slugify(source_stem)

        merged = dict(front_matter_data)
        merged.setdefault("title", inferred_title)
        merged.setdefault("date", inferred_date)
        merged.setdefault("draft", default_draft)
        merged.setdefault("slug", inferred_slug)
        merged.update(sidecar_data)

        if strip_first_h1 and h1_idx is not None:
            final_title = merged.get("title")
            if isinstance(final_title, str) and final_title.strip() == inferred_title.strip():
                stripped_body = strip_first_h1_if_leading(body, h1_idx)
                if stripped_body != body:
                    stats.stripped_h1 += 1
                body = stripped_body

        if rewrite_md_links:
            rewritten_body = rewrite_md_links_in_body(body, current_src_rel_posix=source_rel_path, in_to_out_posix=in_to_out_posix)
            if rewritten_body != body:
                stats.rewritten_link_docs += 1
            body = rewritten_body

        fm_yaml = dump_front_matter_yaml(merged)
        rendered_output = "---\n" + fm_yaml + "---\n\n" + body.lstrip("\r\n")
        if not rendered_output.endswith("\n"):
            rendered_output += "\n"

        with open(output_path, "w", encoding="utf-8", newline="\n") as file_handle:
            file_handle.write(rendered_output)
        stats.files_written += 1

    info("Adaptation summary")
    kv("Markdown", stats.files_written)
    kv("Sidecars", stats.sidecars_applied)
    kv("H1 stripped", stats.stripped_h1)
    kv("Links fixed", stats.rewritten_link_docs)


if __name__ == "__main__":
    main()