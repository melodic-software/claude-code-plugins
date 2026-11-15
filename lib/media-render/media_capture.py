"""HTML -> PNG at a fixed size through Playwright for Python's Chromium, several pages at once (ADR 0103).

capture(pages, width=1920, height=1080, scale=2, concurrency=4) -> [Path]
  pages: [(html text, out png)]. Each page loads with JavaScript off and no network beyond data: URIs, waits for
  fonts, and is shot at width x height CSS pixels times scale (3840x2160 by default).
capture_checked(pages, width, height, scale, band, concurrency=4) -> [(Path, problems)]
  capture, plus the fit check of each page: problems lists every box or line of text in <main> that lies outside
  <main>'s box (cut off by the frame, inside the caption band, or over the <header>), every header part outside
  the header's area, and a <main> that reaches into the bottom band share of the frame. [] when the page fits.
paginate(jobs, width, height, scale, band, concurrency=4) -> [[(start, stop)]]
  jobs: [(render, total)], render(start, stop) -> html showing entries [start, stop) of a list of total entries.
  Per job, the ranges that cover the list in order, each the longest that passes the fit check (at least one
  entry, so an entry too big for any frame gets a frame of its own, which the fit check then reports).
The fit check runs the browser's own layout from outside the page; the page's scripts stay off.
CaptureError when Playwright is missing; ChromiumMissing (a CaptureError) when its Chromium is not downloaded yet.
Both name the install command; install() runs it (INSTALL_ARGS after the Python executable).
"""
import asyncio
import importlib.util
import subprocess
import sys
from pathlib import Path


INSTALL_ARGS = ('-m', 'playwright', 'install', '--only-shell', 'chromium')
INSTALL = 'python ' + ' '.join(INSTALL_ARGS)

FIT = r"""(band) => {
  const main = document.querySelector('main');
  if (!main) return ['the page has no <main> element to measure'];
  const box = main.getBoundingClientRect(), slack = 1, out = [];
  const name = el => el.tagName.toLowerCase() +
    (typeof el.className === 'string' && el.className.trim() ? '.' + el.className.trim().split(/\s+/).join('.') : '');
  const where = (r, area) => {
    const off = [];
    if (r.top < area.top - slack) off.push(`${Math.round(area.top - r.top)} px above`);
    if (r.bottom > area.bottom + slack) off.push(`${Math.round(r.bottom - area.bottom)} px below`);
    if (r.left < area.left - slack) off.push(`${Math.round(area.left - r.left)} px left of`);
    if (r.right > area.right + slack) off.push(`${Math.round(r.right - area.right)} px right of`);
    return off.join(' and ');
  };
  const floor = innerHeight - band;
  if (box.bottom > floor + slack || box.top < -slack)
    out.push(`<main> reaches ${Math.round(box.bottom - floor)} px into the caption band or off the frame`);
  const walk = document.createTreeWalker(main, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT);
  for (let n = walk.nextNode(); n; n = walk.nextNode()) {
    const rects = [];
    if (n.nodeType === 1) rects.push(n.getBoundingClientRect());
    else if (n.textContent.trim()) {
      const range = document.createRange();
      range.selectNodeContents(n);
      rects.push(...range.getClientRects());
    }
    for (const r of rects) {
      if (!r.width || !r.height) continue;
      const off = where(r, box);
      if (off) out.push(`${n.nodeType === 1 ? 'box ' + name(n) : 'text in ' + name(n.parentElement)} lies ${off} the content area`);
    }
  }
  const head = document.querySelector('header');
  if (head) {
    const area = {top: 0, left: 0, right: innerWidth, bottom: box.top};
    for (const el of [head, ...head.querySelectorAll('*')]) {
      const off = where(el.getBoundingClientRect(), area);
      if (off) out.push(`header ${name(el)} lies ${off} the header area`);
    }
  }
  return [...new Set(out)];
}"""


class CaptureError(RuntimeError):
    pass


class ChromiumMissing(CaptureError):
    pass


async def _load(browser, html, width, height, scale):
    context = await browser.new_context(viewport={'width': width, 'height': height}, device_scale_factor=scale,
                                        java_script_enabled=False, offline=True)
    page = await context.new_page()
    await page.route('**/*', lambda route: route.abort() if not route.request.url.startswith('data:')
                     else route.continue_())
    await page.set_content(html, wait_until='load')
    return context, page


async def _shoot(browser, html, out, width, height, scale, gate, band=None):
    """(png, problems); no png when out is None, and no fit check (problems None) when band is None."""
    async with gate:
        context, page = await _load(browser, html, width, height, scale)
        try:
            problems = await page.evaluate(FIT, round(height * band)) if band is not None else None
            if out is not None:
                await page.screenshot(path=str(out), full_page=False, animations='disabled')
        finally:
            await context.close()
    return (Path(out) if out is not None else None), problems


async def _split(browser, render, total, width, height, scale, band, gate):
    async def fits(a, b):
        return not (await _shoot(browser, render(a, b), None, width, height, scale, gate, band))[1]
    cuts, start = [], 0
    while start < total:
        good, bad = 1, total - start + 1
        if await fits(start, total):
            good = total - start
        else:
            bad = total - start
            while bad - good > 1:
                mid = (good + bad) // 2
                if await fits(start, start + mid):
                    good = mid
                else:
                    bad = mid
        cuts.append((start, start + good))
        start += good
    return cuts


async def _browse(work):
    from playwright.async_api import async_playwright
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        try:
            return await work(browser)
        finally:
            await browser.close()


def _run(work):
    if importlib.util.find_spec('playwright') is None:
        raise CaptureError('Playwright for Python is not installed: install the plugin requirements, then run '
                           f'`{INSTALL}`')
    try:
        return asyncio.run(_browse(work))
    except Exception as e:
        if 'Executable doesn\'t exist' in str(e):
            raise ChromiumMissing(f'Playwright\'s Chromium is missing: run `{INSTALL}`') from e
        raise


def install(timeout):
    """Download Playwright's Chromium headless shell for this Python."""
    subprocess.run([sys.executable, *INSTALL_ARGS], check=True, timeout=timeout)


def capture_checked(pages, width, height, scale, band, concurrency=4):
    gate = asyncio.Semaphore(concurrency)
    return _run(lambda browser: asyncio.gather(*(_shoot(browser, h, o, width, height, scale, gate, band)
                                                 for h, o in pages)))


def capture(pages, width=1920, height=1080, scale=2, concurrency=4):
    gate = asyncio.Semaphore(concurrency)
    shots = _run(lambda browser: asyncio.gather(*(_shoot(browser, h, o, width, height, scale, gate)
                                                  for h, o in pages)))
    return [png for png, _ in shots]


def paginate(jobs, width, height, scale, band, concurrency=4):
    if not jobs:
        return []
    gate = asyncio.Semaphore(concurrency)
    return _run(lambda browser: asyncio.gather(*(_split(browser, render, total, width, height, scale, band, gate)
                                                 for render, total in jobs)))
