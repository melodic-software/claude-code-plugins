#!/usr/bin/env python3
"""Resolve the plugin's configuration through the config cascade (design T4).

Layers, in resolution order, each optional, merged by per-key override (a
later layer replaces an earlier layer's value key by key; a key absent from a
later layer keeps the earlier value; a list is a closed value and is replaced
whole):

  0. bundled defaults           scripts/config-defaults.json
  1. user-global                ~/.claude/code-metrics.yaml
  2. team                       <repo>/docs/conventions/code-metrics.yaml, or
                                <repo>/.claude/code-metrics.yaml when that is absent
  3. local overlay              <repo>/.claude/code-metrics.local.yaml

The team layer is one file: with both present the docs/conventions file is the
whole layer and a warning names both paths.

An invalid layer never stops the run. A file outside the YAML subset is named
and read as absent. A value of the wrong shape (a scalar where a list or a
mapping belongs, a quoted number for a reference, a control character, an
exclude glob the matcher cannot compile) is named with its file, key and value
and dropped: the key resolves from a valid higher layer, else the bundled
default, never from a lower layer.

The consumer's ecosystem files (`.claude/ecosystems/<lane>.yaml`, the
marketplace-wide ecosystem-commands convention) resolve through the same three
layers for their `globs` and `enabled` keys.

Usage:
  resolve-config.py [options] [<user.yaml> [<team.yaml> [<local.yaml>]]]

Positional files stand in for the three layers in that order (the suites use
them); otherwise the layers are discovered from --home (default $HOME) and
--repo-root (default the git top level, else the working directory).

Options:
  --defaults <file>        bundled defaults (default: config-defaults.json beside this script)
  --ladder <file>          validate `lanes.<lane>.collectors.<measure>` names against the ladder
  --format json            the resolved document (default): every key, plus `_layers`
                           (dotted key -> the layer that supplied it), `_provenance`
                           (dotted key -> {value, layer}), `_files` (the layer files read),
                           `_ecosystems` (lane -> {globs, enabled, layer}), `_warnings`
  --format dispatch-args   one dispatcher option per line: `--lane-globs <lane>=<g1,g2>`
                           for a lane whose ecosystem file declares globs, `--disable-lane
                           <lane>` for a lane resolved to enabled: false
  --format ladder-overrides
                           `lane<TAB>measure<TAB>tool` rows from `lanes.<lane>.collectors`
  --format excludes        one `scope.exclude` glob per line
  --format registries      one sanctioned-replication registry path per line:
                           `scope.registries`, or `duplication.registries` when the
                           scope-level list is empty (the older key is an alias)
  --from-json <file>       skip resolution and derive the format from a document this
                           script printed earlier (the dispatcher's `--config` path)

Exit 0 on success, warnings included; 2 for a usage error, or for a
`--from-json` document whose line-oriented field would break its line.
"""

from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import os
import re
import subprocess
import sys
from typing import Any

MIN_PYTHON = (3, 9)


class ConfigTypeError(ValueError):
    """A resolved value has a type the plugin cannot compare (a quoted number)."""


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LAYER_NAMES = ("user-global", "team", "local")
SURFACE = "code-metrics"


def _module(name: str) -> Any:
    spec = importlib.util.spec_from_file_location(
        name, os.path.join(SCRIPT_DIR, f"{name}.py")
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


yaml_subset = _module("yaml_subset")
pathglob = _module("pathglob")

CONTROL = re.compile(r"[\n\r\t]")
# Lists whose items the schema types as strings; a number or a nested value
# in one is a wrong shape, not a rule id.
STRING_LISTS = {"suppressions.correctness_rules"}


def _reserved(key: str) -> bool:
    """A key no layer may supply: the resolver's own `_` outputs, and `thresholds`."""
    return key.startswith("_") or key == "thresholds"


def _load_layer(path: str, warnings: list[str]) -> dict[str, Any] | None:
    """The layer's mapping, or None (with a warning) when it cannot be read."""
    try:
        value = yaml_subset.load(path)
        if value is not None and not isinstance(value, dict):
            raise yaml_subset.YamlSubsetError(1, "the top level must be a mapping")
    except yaml_subset.YamlSubsetError as exc:
        warnings.append(f"{path}: outside the YAML subset ({exc}); layer ignored")
        return None
    return value or {}


_MISSING = object()


def _lookup(node: Any, parts: list[str]) -> Any:
    for part in parts:
        if not isinstance(node, dict) or part not in node:
            return _MISSING
        node = node[part]
    return node


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _invalid(
    key: str, value: Any, defaults: dict[str, Any], threshold_keys: set[str]
) -> str | None:
    """Why a layer's value for `key` cannot be used, or None when it can."""
    parts = key.split(".")
    scalars = value if isinstance(value, list) else [value]
    if CONTROL.search(key) or any(
        isinstance(item, str) and CONTROL.search(item) for item in scalars
    ):
        return (
            "a control character (newline, carriage return or tab) would break "
            "the resolver's line-oriented output"
        )
    if key in threshold_keys and not (value is None or _is_number(value)):
        return "a reference must be a number or null"
    default = _lookup(defaults, parts)
    if isinstance(default, dict):
        return "must be a mapping"
    collectors = len(parts) == 4 and parts[0] == "lanes" and parts[2] == "collectors"
    if (isinstance(default, list) or collectors) and not (
        value is None or isinstance(value, list)
    ):
        return "must be a list or null"
    if key in STRING_LISTS and isinstance(value, list):
        if not all(isinstance(item, str) for item in value):
            return "every item must be a string"
    if key == "scope.exclude" and isinstance(value, list):
        for glob in value:
            try:
                re.compile(pathglob.translate(str(glob)))
            except re.error as exc:
                return f"{str(glob)!r} is not a usable glob ({exc})"
    return None


def _drop(node: dict[str, Any], parts: list[str]) -> None:
    for part in parts[:-1]:
        node = node[part]
    del node[parts[-1]]


def _reset(
    config: dict[str, Any],
    defaults: dict[str, Any],
    parts: list[str],
    layers: dict[str, str],
) -> None:
    """Put `parts` back to its bundled default, discarding lower layers' values."""
    default = _lookup(defaults, parts)
    parent: Any = config
    for part in parts[:-1]:
        child = parent.get(part)
        if not isinstance(child, dict):
            if default is _MISSING:
                break
            child = parent[part] = {}
        parent = child
    else:
        if default is _MISSING:
            parent.pop(parts[-1], None)
        else:
            parent[parts[-1]] = copy.deepcopy(default)
    dotted = ".".join(parts)
    for key in [k for k in layers if k == dotted or k.startswith(dotted + ".")]:
        del layers[key]


def merge(
    base: Any, overlay: Any, layer: str, prefix: str, layers: dict[str, str]
) -> Any:
    if isinstance(base, dict) and isinstance(overlay, dict):
        result = dict(base)
        for key, value in overlay.items():
            dotted = f"{prefix}.{key}" if prefix else key
            result[key] = merge(base.get(key), value, layer, dotted, layers)
        return result
    layers[prefix] = layer
    return overlay


def _walk(node: Any, prefix: str, out: dict[str, Any]) -> None:
    if isinstance(node, dict):
        for key, value in node.items():
            _walk(value, f"{prefix}.{key}" if prefix else key, out)
    else:
        out[prefix] = node


def repo_root() -> str:
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=False,
        )
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip().replace("\\", "/")
    except OSError:
        pass
    return os.getcwd().replace("\\", "/")


def layer_paths(home: str, root: str, stem: str) -> list[tuple[str, str]]:
    return [
        ("user-global", os.path.join(home, ".claude", f"{stem}.yaml")),
        ("team", os.path.join(root, ".claude", f"{stem}.yaml")),
        ("local", os.path.join(root, ".claude", f"{stem}.local.yaml")),
    ]


def surface_layer_paths(
    home: str, root: str, warnings: list[str]
) -> list[tuple[str, str]]:
    """The plugin's own three layers; the team layer prefers the docs home.

    `docs/conventions/code-metrics.yaml` is the team layer (ADR 0054). The
    older `.claude/code-metrics.yaml` is read only when the docs file is
    absent, so a repository configured by an earlier release keeps its values.
    """
    paths = layer_paths(home, root, SURFACE)
    legacy = paths[1][1]
    docs = os.path.join(root, "docs", "conventions", f"{SURFACE}.yaml")
    if os.path.isfile(docs):
        if os.path.isfile(legacy):
            warnings.append(
                f"{docs} and {legacy} both exist; the team layer is {docs} and "
                f"{legacy} is not read (delete it once no older plugin release reads it)"
            )
        paths[1] = ("team", docs)
    return paths


def resolve(
    defaults_path: str,
    layer_files: list[tuple[str, str]],
    ecosystem_files: dict[str, list[tuple[str, str]]],
    ladder_path: str | None,
    warnings: list[str] | None = None,
) -> dict[str, Any]:
    with open(defaults_path, encoding="utf-8") as handle:
        config: Any = json.load(handle)
    defaults = copy.deepcopy(config)
    threshold_keys = {
        str(entry.get("config_key"))
        for entry in defaults.get("thresholds") or []
        if entry.get("config_key")
    }
    layers: dict[str, str] = {}
    files_read: list[str] = []
    warnings = [] if warnings is None else warnings
    for layer, path in layer_files:
        if not os.path.isfile(path):
            continue
        overlay = _load_layer(path, warnings)
        if overlay is None:
            continue
        for key in overlay:
            if _reserved(key):
                warnings.append(f"{path}: key {key!r} is reserved and ignored")
        overlay = {k: v for k, v in overlay.items() if not _reserved(k)}
        leaves: dict[str, Any] = {}
        _walk(overlay, "", leaves)
        for key, value in leaves.items():
            reason = _invalid(key, value, defaults, threshold_keys)
            if reason is None:
                continue
            warnings.append(
                f"{path}: {key} = {value!r}: {reason}; this layer's value is "
                "dropped and the key resolves from a higher layer or the bundled default"
            )
            parts = key.split(".")
            _drop(overlay, parts)
            _reset(config, defaults, parts, layers)
        config = merge(config, overlay, layer, "", layers)
        files_read.append(path.replace("\\", "/"))
    if ladder_path:
        known: set[tuple[str, str, str]] = set()
        with open(ladder_path, encoding="utf-8") as handle:
            for raw in handle:
                if raw.startswith("#") or not raw.strip():
                    continue
                parts = raw.rstrip("\n").split("\t")
                if len(parts) >= 3:
                    known.add((parts[0], parts[1], parts[2]))
        for lane, lane_cfg in (config.get("lanes") or {}).items():
            collectors = (lane_cfg or {}).get("collectors") or {}
            for measure, tools in list(collectors.items()):
                if not isinstance(tools, list):
                    warnings.append(
                        f"lanes.{lane}.collectors.{measure}: expected a list; ignored"
                    )
                    del collectors[measure]
                    continue
                kept = []
                for tool in tools:
                    if (lane, measure, str(tool)) in known or (
                        lane,
                        "*",
                        str(tool),
                    ) in known:
                        kept.append(str(tool))
                    else:
                        warnings.append(
                            f"lanes.{lane}.collectors.{measure}: {tool!r} is not in the ladder for {lane}/{measure}; dropped"
                        )
                collectors[measure] = kept
    ecosystems: dict[str, Any] = {}
    for lane, files in ecosystem_files.items():
        eco: dict[str, Any] = {}
        eco_layers: dict[str, str] = {}
        for layer, path in files:
            if not os.path.isfile(path):
                continue
            overlay = _load_layer(path, warnings)
            if overlay is None:
                continue
            eco = merge(eco, overlay, layer, "", eco_layers)
            files_read.append(path.replace("\\", "/"))
        if not eco:
            continue
        globs = eco.get("globs")
        enabled = eco.get("enabled", True)
        ecosystems[lane] = {
            "globs": [str(g) for g in globs] if isinstance(globs, list) else None,
            "enabled": bool(enabled) if enabled is not None else True,
            "layer": eco_layers.get("globs") or eco_layers.get("enabled") or "team",
        }
    flat: dict[str, Any] = {}
    _walk({k: v for k, v in config.items() if not _reserved(k)}, "", flat)
    provenance = {
        key: {"value": value, "layer": layers.get(key, "bundled default")}
        for key, value in flat.items()
    }
    config["_layers"] = layers
    config["_provenance"] = provenance
    config["_files"] = files_read
    config["_ecosystems"] = ecosystems
    config["_warnings"] = warnings
    return config


def _field(config: dict[str, Any], key: str, value: Any, tabs: bool = False) -> str:
    """One field of a line-oriented output format.

    `dispatch-args`, `ladder-overrides` and `excludes` are read a line at a
    time (the dispatcher uses `mapfile`, then dispatches on the first word),
    and the ladder rows are tab separated. The YAML subset's double-quoted
    scalars support a real `\\n` escape, so without this a layer could write
    `base: "auto\\n--disable-lane python"` and have one scalar key arrive as
    two directives, the second of them silently narrowing what gets measured.
    A field that would break out of its line, or out of its column, is refused
    by key instead of obeyed.
    """
    text = str(value)
    bad = [
        name
        for ch, name in (("\n", "newline"), ("\r", "carriage return"))
        if ch in text
    ]
    if tabs and "\t" in text:
        bad.append("tab")
    if not bad:
        return text
    layer = (config.get("_layers") or {}).get(key)
    where = f" (layer {layer})" if layer else ""
    raise ConfigTypeError(
        f"{key}{where} must not contain a {' or '.join(bad)}: the resolver's "
        f"output is line oriented, so {text!r} would reach the dispatcher as "
        "more than one directive"
    )


def dispatch_args(config: dict[str, Any]) -> list[str]:
    lines: list[str] = []
    # A configured `all` default and a configured base travel to the dispatcher,
    # which lets an explicit command-line --all, path, or --base win over them.
    # `change` is the bundled default and the dispatcher's own, so it emits
    # nothing: a no-op line would only be noise on the dispatcher's command line.
    scope = config.get("scope") or {}
    default = scope.get("default")
    if default == "all":
        lines.append(f"--scope-default {default}")
    base = scope.get("base")
    if isinstance(base, str) and base.strip() and base != "auto":
        lines.append(f"--scope-base {_field(config, 'scope.base', base.strip())}")
    lanes = config.get("lanes") or {}
    ecosystems = config.get("_ecosystems") or {}
    for lane in sorted(set(lanes) | set(ecosystems)):
        eco = ecosystems.get(lane) or {}
        plugin_enabled = (lanes.get(lane) or {}).get("enabled", True)
        enabled = eco.get("enabled", True) if eco else True
        name = _field(config, "lanes.<lane>", lane)
        if plugin_enabled is False or enabled is False:
            lines.append(f"--disable-lane {name}")
            continue
        if eco.get("globs"):
            globs = ",".join(
                _field(config, f"ecosystems.{name}.globs", glob)
                for glob in eco["globs"]
            )
            lines.append(f"--lane-globs {name}={globs}")
    return lines


def ladder_overrides(config: dict[str, Any]) -> list[str]:
    lines: list[str] = []
    for lane, lane_cfg in sorted((config.get("lanes") or {}).items()):
        name = _field(config, "lanes.<lane>", lane, tabs=True)
        for measure, tools in sorted(
            ((lane_cfg or {}).get("collectors") or {}).items()
        ):
            key = f"lanes.{name}.collectors.<measure>"
            column = _field(config, key, measure, tabs=True)
            if not tools:
                # An explicitly empty list is a closed value: no collector runs
                # for this lane and measure, so the dispatcher gets the
                # reserved `none` rung rather than falling back to the ladder.
                lines.append(f"{name}\t{column}\tnone")
                continue
            for tool in tools:
                lines.append(
                    f"{name}\t{column}\t{_field(config, key, tool, tabs=True)}"
                )
    return lines


def excludes(config: dict[str, Any]) -> list[str]:
    patterns = (config.get("scope") or {}).get("exclude")
    if patterns is None:
        patterns = []
    # `scope.exclude` is a closed list. A scalar (`exclude: "vendor/**"`, the
    # shape setup-apply.py writes for a one-glob value) iterates as characters,
    # so the dispatcher would receive `v`, `e`, `n`, ... as globs: the audit
    # exits 0 having measured the directory it was told to drop, and having
    # possibly dropped unrelated single-character paths.
    if not isinstance(patterns, list):
        layer = (config.get("_layers") or {}).get("scope.exclude", "bundled default")
        raise ConfigTypeError(
            f"scope.exclude (layer {layer}) must be a list of globs or null, "
            f"got {type(patterns).__name__} {patterns!r}"
        )
    return [_field(config, "scope.exclude", p) for p in patterns if str(p).strip()]


def registries(config: dict[str, Any]) -> list[str]:
    """The sanctioned-replication registries every audit applies.

    `scope.registries` is the key; `duplication.registries` is its older name
    and still resolves when the scope-level list is empty, so a team file
    written before the key moved keeps working unchanged. Both are closed
    lists; a scalar is refused for the reason `excludes` refuses one.
    """
    scope_list = (config.get("scope") or {}).get("registries")
    dup_list = (config.get("duplication") or {}).get("registries")
    for key, value in (
        ("scope.registries", scope_list),
        ("duplication.registries", dup_list),
    ):
        if value is not None and not isinstance(value, list):
            layer = (config.get("_layers") or {}).get(key, "bundled default")
            raise ConfigTypeError(
                f"{key} (layer {layer}) must be a list of registry paths or null, "
                f"got {type(value).__name__} {value!r}"
            )
    chosen, key = (scope_list, "scope.registries")
    if not chosen:
        chosen, key = (dup_list or [], "duplication.registries")
    return [_field(config, key, p) for p in chosen if str(p).strip()]


def emit_or_fail(config: dict[str, Any], fmt: str) -> int:
    """Write one format, turning a refused field into exit 2 with its message.

    The `--from-json` path never runs `resolve()`, so a field guard that only
    fired there would be skipped by exactly the caller the dispatcher uses.
    Both entry points come through here instead.
    """
    try:
        emit(config, fmt)
    except ConfigTypeError as exc:
        print(f"resolve-config.py: {exc}", file=sys.stderr)
        return 2
    return 0


# The line-oriented formats, each a builder of the lines it prints; every other
# format is the resolved document itself.
LINE_FORMATS = {
    "dispatch-args": dispatch_args,
    "ladder-overrides": ladder_overrides,
    "excludes": excludes,
    "registries": registries,
}


def emit(config: dict[str, Any], fmt: str) -> None:
    build = LINE_FORMATS.get(fmt)
    if build is None:
        print(json.dumps(config, indent=2))
        return
    sys.stdout.write("".join(line + "\n" for line in build(config)))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="resolve-config.py", add_help=True)
    parser.add_argument("layers", nargs="*")
    parser.add_argument(
        "--defaults", default=os.path.join(SCRIPT_DIR, "config-defaults.json")
    )
    parser.add_argument("--ladder")
    parser.add_argument(
        "--home", default=os.environ.get("HOME") or os.path.expanduser("~")
    )
    parser.add_argument("--repo-root")
    parser.add_argument("--from-json")
    parser.add_argument(
        "--format",
        choices=("json", "dispatch-args", "ladder-overrides", "excludes", "registries"),
        default="json",
    )
    args = parser.parse_args(argv)
    if args.from_json:
        try:
            with open(args.from_json, encoding="utf-8") as handle:
                config = json.load(handle)
        except (OSError, json.JSONDecodeError) as exc:
            print(f"resolve-config.py: {args.from_json}: {exc}", file=sys.stderr)
            return 2
        return emit_or_fail(config, args.format)
    if len(args.layers) > 3:
        print(
            "resolve-config.py: at most three positional layer files (user, team, local)",
            file=sys.stderr,
        )
        return 2
    root = (args.repo_root or repo_root()).replace("\\", "/")
    warnings: list[str] = []
    if args.layers:
        layer_files = [(LAYER_NAMES[i], path) for i, path in enumerate(args.layers)]
        for _, path in layer_files:
            if not os.path.isfile(path):
                print(
                    f"resolve-config.py: layer file does not exist: {path}",
                    file=sys.stderr,
                )
                return 2
        ecosystem_files: dict[str, list[tuple[str, str]]] = {}
    else:
        layer_files = surface_layer_paths(args.home, root, warnings)
        with open(args.defaults, encoding="utf-8") as handle:
            lane_names = list((json.load(handle).get("lanes") or {}).keys())
        ecosystem_files = {
            lane: layer_paths(args.home, root, os.path.join("ecosystems", lane))
            for lane in lane_names
        }
    try:
        config = resolve(
            args.defaults, layer_files, ecosystem_files, args.ladder, warnings
        )
    except OSError as exc:
        print(f"resolve-config.py: {exc}", file=sys.stderr)
        return 2
    for warning in config.get("_warnings", []):
        print(f"resolve-config.py: warning: {warning}", file=sys.stderr)
    return emit_or_fail(config, args.format)


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print(
            "resolve-config.py needs Python %d.%d or later" % MIN_PYTHON,
            file=sys.stderr,
        )
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
