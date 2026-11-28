"""Shared branding bridge for planning's Python interview servers.

Calls the plugin's bundled `lib/view-settings.mjs branding` resolver and renders
the fixed `.rv-brand` slot HTML/CSS matching `lib/html-branding.mjs`.
"""

from __future__ import annotations

import html
import json
import os
import subprocess
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parent.parent
VIEW_SETTINGS = PLUGIN_ROOT / "lib" / "view-settings.mjs"
TOKENS_FILE = PLUGIN_ROOT / "reference" / "html-tokens.css"

LOGO_SLOT_CSS = "\n".join(
    (
        ".rv-brand { display: inline-flex; align-items: center; gap: 0.5rem; margin-right: auto; }",
        ".rv-brand svg { height: 1.5rem; width: auto; display: block; }",
        ".rv-brand-mark { display: inline-block; width: 1.5rem; height: 1.5rem; background-size: contain; background-repeat: no-repeat; background-position: center; }",
        ".rv-brand-label { font-family: var(--sans); font-weight: 600; font-size: 0.95rem; color: var(--fg); }",
    )
)

EMPTY = {"css": "", "slot_html": "", "logo": {"kind": None, "label": None}, "notices": [], "has_overrides": False}


def logo_slot_html(logo: dict | None) -> str:
    if not isinstance(logo, dict):
        return ""
    kind = logo.get("kind")
    label = logo.get("label") or ""
    if not kind and not label:
        return ""
    parts: list[str] = []
    if kind == "svg" and logo.get("svg"):
        parts.append(str(logo["svg"]))
    elif kind == "image" and logo.get("dataUrl"):
        aria = html.escape(label or "Brand logo", quote=True)
        parts.append(f'<span class="rv-brand-mark rv-logo" role="img" aria-label="{aria}"></span>')
    if label:
        parts.append(f'<span class="rv-brand-label">{html.escape(label, quote=True)}</span>')
    return f'<div class="rv-brand">{"".join(parts)}</div>'


def logo_slot_css(logo: dict | None) -> str:
    if not isinstance(logo, dict):
        return ""
    if not logo.get("kind") and not logo.get("label"):
        return ""
    return LOGO_SLOT_CSS


def _installed_branding_option() -> str | None:
    """Read `userConfig.branding` from Claude Code settings when no explicit option was given."""
    parts = PLUGIN_ROOT.as_posix().split("/")
    plugin_id = None
    settings_path = None
    if "cache" in parts:
        idx = len(parts) - 1 - parts[::-1].index("cache")
        if idx > 0 and parts[idx - 1] == "plugins" and len(parts) - idx == 4 and all(parts[idx + 1 :]):
            marketplace, name = parts[idx + 1], parts[idx + 2]
            plugin_id = f"{name}@{marketplace}"
            config_root = "/".join(parts[: idx - 1]) or "/"
            settings_path = Path(config_root) / "settings.json"
    if settings_path is None:
        cfg_dir = os.environ.get("CLAUDE_CONFIG_DIR")
        if not cfg_dir:
            return None
        settings_path = Path(cfg_dir) / "settings.json"
    try:
        data = json.loads(settings_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    configs = data.get("pluginConfigs") if isinstance(data, dict) else None
    if not isinstance(configs, dict):
        return None
    for key in sorted(configs):
        if plugin_id is not None and key != plugin_id:
            continue
        if plugin_id is None and key != "planning" and not key.startswith("planning@"):
            continue
        entry = configs.get(key)
        opts = entry.get("options") if isinstance(entry, dict) else None
        val = opts.get("branding") if isinstance(opts, dict) else None
        if isinstance(val, str) and val:
            return val
    return None


def resolve_branding(project_root: Path | str | None = None, *, option: str | None = None, team_ref: str | None = None) -> dict:
    """Resolve branding for `project_root` via `lib/view-settings.mjs branding`."""
    if not VIEW_SETTINGS.is_file():
        return dict(EMPTY)
    if option is None:
        option = _installed_branding_option()
    cmd = ["node", str(VIEW_SETTINGS), "branding"]
    if option:
        cmd.extend(["--option", option])
    if team_ref:
        cmd.extend(["--team-ref", team_ref])
    cwd = str(project_root) if project_root and Path(project_root).is_dir() else None
    env = os.environ.copy()
    if cwd:
        env["CLAUDE_PROJECT_DIR"] = cwd
    else:
        env.pop("CLAUDE_PROJECT_DIR", None)
    try:
        proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=10, check=False, env=env)
    except (OSError, subprocess.SubprocessError):
        return dict(EMPTY)
    if proc.returncode != 0:
        return dict(EMPTY)
    first = (proc.stdout.splitlines() or [""])[0]
    try:
        data = json.loads(first)
    except ValueError:
        return dict(EMPTY)
    logo = data.get("logo") if isinstance(data.get("logo"), dict) else {"kind": None, "label": None}
    slot_css = logo_slot_css(logo)
    raw_css = str(data.get("css") or "")
    combined_css = "\n".join(part for part in (slot_css, raw_css) if part)
    return {
        "css": combined_css,
        "slot_html": logo_slot_html(logo),
        "logo": logo,
        "notices": list(data.get("notices") or []),
        "has_overrides": bool(data.get("hasOverrides")),
    }
