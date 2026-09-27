#!/usr/bin/env python3
"""Write index.html in an output directory: every PNG, GIF and HTML scene on one page, scaled crisp.

Usage: gallery.py <dir> [<dir> ...]   (one page per directory; prints each page path)
"""
import html
import pathlib
import sys

PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>{title}</title>
<style>
body {{ margin: 0; padding: 24px; background: #16141f; color: #e8e4f0; font: 14px system-ui, sans-serif; }}
h1 {{ font-size: 18px; margin: 0 0 16px; }}
.grid {{ display: flex; flex-wrap: wrap; gap: 20px; align-items: flex-start; }}
figure {{ margin: 0; background: #221f2e; padding: 12px; border-radius: 6px; }}
figcaption {{ margin-top: 8px; font-family: ui-monospace, monospace; font-size: 12px; color: #a8a0bc; }}
img {{ image-rendering: pixelated; display: block;
       background: repeating-conic-gradient(#2c2838 0 25%, #34303f 0 50%) 0 0 / 16px 16px; }}
iframe {{ border: 0; display: block; background: #000; }}
</style></head><body>
<h1>{title}</h1>
<div class="grid">
{items}
</div></body></html>
"""


def figure(inner, name):
    return f"<figure>{inner}<figcaption>{html.escape(name)}</figcaption></figure>"


def build(directory):
    directory = pathlib.Path(directory)
    items = []
    for path in sorted(directory.iterdir()):
        name = html.escape(path.name)
        if path.name == "index.html":
            continue
        if path.suffix == ".gif":
            items.append(figure(f'<img src="{name}" alt="{name}" style="width:192px">', path.name))
        elif path.suffix == ".png" and path.name != "sheet.png":
            items.append(figure(f'<img src="{name}" alt="{name}" style="max-width:720px">', path.name))
        elif path.suffix == ".html":
            items.append(figure(f'<iframe src="{name}" title="{name}" width="720" height="480"></iframe>'
                                f'<a href="{name}" style="color:#c8b8ff">open full size</a>', path.name))
    page = directory / "index.html"
    page.write_text(PAGE.format(title=html.escape(directory.resolve().name), items="\n".join(items)))
    return page


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for d in sys.argv[1:]:
        print(build(d))
