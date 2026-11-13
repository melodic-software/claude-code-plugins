"""Frame templates: one storyboard moment -> one self-contained HTML page at a fixed 1920x1080 CSS size.

page(moment, board_title, chapter_title, position, stylesheet=None, base_dir=None) -> html
  Every string from the storyboard is HTML-escaped; class names come only from fixed sets, never from data.
  stylesheet: CSS text replacing the bundled frames.css (config `frame_stylesheet`).
  base_dir: where a screenshot moment's image path resolves; the image is inlined as a data URI.
frame_text(moment, board_title, chapter_title) -> every string a frame shows, for the scan.
Standard library only.
"""
import base64
import html
from pathlib import Path

STYLESHEET = Path(__file__).with_name('frames.css')
LINE_KINDS = {'+': 'add', '-': 'del', ' ': 'ctx'}
RISK_LEVELS = ('low', 'medium', 'high', 'critical')
IMAGE_TYPES = {'.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp'}


def e(value):
    return html.escape(str(value if value is not None else ''), quote=True)


def _lines(items):
    return ''.join(f'<div class="ln">{e(t)}</div>' for t in items or [])


def _title(d, board_title):
    sub = f'<p class="subtitle">{e(d.get("subtitle"))}</p>' if d.get('subtitle') else ''
    return f'<section class="title"><h1>{e(board_title)}</h1>{sub}</section>'


def _code_hunk(d):
    rows = []
    for ln in d.get('lines') or []:
        kind = LINE_KINDS.get(ln.get('kind', ' '), 'ctx')
        mark = {'add': '+', 'del': '−', 'ctx': ' '}[kind]
        rows.append(f'<tr class="{kind}"><td class="n">{e(ln.get("n", ""))}</td><td class="m">{mark}</td>'
                    f'<td class="t">{e(ln.get("text", ""))}</td></tr>')
    note = f'<p class="note">{e(d["note"])}</p>' if d.get('note') else ''
    return (f'<section class="code"><div class="path">{e(d.get("path"))}</div>'
            f'<table class="hunk">{"".join(rows)}</table>{note}</section>')


def _diagram(d):
    nodes = []
    for n in d.get('nodes') or []:
        detail = f'<div class="detail">{e(n.get("detail"))}</div>' if n.get('detail') else ''
        nodes.append(f'<div class="node"><div class="label">{e(n.get("label"))}</div>{detail}</div>')
    note = f'<p class="note">{e(d["note"])}</p>' if d.get('note') else ''
    return f'<section class="diagram"><div class="flow">{"<div class=arrow>→</div>".join(nodes)}</div>{note}</section>'


def _before_after(d):
    def side(cls, s):
        s = s or {}
        return f'<div class="side {cls}"><h2>{e(s.get("label", cls.title()))}</h2><div class="body">{_lines(s.get("lines"))}</div></div>'
    return f'<section class="before-after">{side("before", d.get("before"))}{side("after", d.get("after"))}</section>'


def _risk_map(d):
    rows = []
    for r in d.get('rows') or []:
        level = r.get('level') if r.get('level') in RISK_LEVELS else 'medium'
        rows.append(f'<tr><td class="area">{e(r.get("area"))}</td><td><span class="risk {level}">{level}</span></td>'
                    f'<td class="note">{e(r.get("note"))}</td></tr>')
    return f'<section class="risk-map"><table>{"".join(rows)}</table></section>'


def _also_changed(d):
    rows = ''.join(f'<li><span class="path">{e(f.get("path"))}</span><span class="summary">{e(f.get("summary"))}</span></li>'
                   for f in d.get('files') or [])
    return f'<section class="also-changed"><h2>Also changed</h2><ul>{rows}</ul></section>'


def inside(base_dir, rel):
    """base_dir / rel with symlinks resolved; ValueError when it lands outside base_dir."""
    base = Path(base_dir or '.').resolve()
    path = (base / str(rel)).resolve()
    if not path.is_relative_to(base):
        raise ValueError(f'{rel!r} resolves outside the storyboard folder')
    return path


def _screenshot(d, base_dir):
    path = inside(base_dir, d.get('image', ''))
    mime = IMAGE_TYPES.get(path.suffix.lower())
    if not mime or not path.is_file():
        raise ValueError(f'screenshot image {d.get("image")!r} is not a readable png, jpeg or webp file')
    data = base64.b64encode(path.read_bytes()).decode()
    caption = f'<p class="note">{e(d["caption"])}</p>' if d.get('caption') else ''
    return f'<section class="screenshot"><img alt="{e(d.get("alt"))}" src="data:{mime};base64,{data}">{caption}</section>'


def page(moment, board_title, chapter_title, position, stylesheet=None, base_dir=None):
    d, t = moment.get('data') or {}, moment['template']
    body = {'title': lambda: _title(d, board_title), 'code-hunk': lambda: _code_hunk(d),
            'diagram': lambda: _diagram(d), 'before-after': lambda: _before_after(d),
            'risk-map': lambda: _risk_map(d), 'also-changed': lambda: _also_changed(d),
            'screenshot': lambda: _screenshot(d, base_dir)}[t]()
    css = stylesheet if stylesheet is not None else STYLESHEET.read_text(encoding='utf-8')
    k, n = position
    return ('<!doctype html><html><head><meta charset="utf-8"><style>' + css.replace('</', '<\\/') + '</style></head>'
            f'<body class="t-{t}"><header><span class="chapter">{e(chapter_title)}</span>'
            f'<span class="pos">{k} / {n}</span></header><main>{body}</main></body></html>')


def frame_text(moment, board_title, chapter_title):
    """Every string a frame shows (for media_scan), without markup; a screenshot's text is its sidecar's."""
    out = [board_title, chapter_title]

    def walk(v):
        if isinstance(v, dict):
            for k, x in v.items():
                if k not in ('image', 'sidecar'):
                    walk(x)
        elif isinstance(v, list):
            for x in v:
                walk(x)
        elif v is not None:
            out.append(str(v))
    walk(moment.get('data') or {})
    return '\n'.join(out)
