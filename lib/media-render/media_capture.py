"""HTML -> PNG at a fixed size through Playwright for Python's Chromium, several pages at once (ADR 0103).

capture(pages, width=1920, height=1080, scale=2, concurrency=4) -> [Path]
  pages: [(html text, out png)]. Each page loads with JavaScript off and no network beyond data: URIs, waits for
  fonts, and is shot at width x height CSS pixels times scale (3840x2160 by default).
CaptureError when Playwright is missing; ChromiumMissing (a CaptureError) when its Chromium is not downloaded yet.
Both name INSTALL, the one install command.
"""
import asyncio
import importlib.util
from pathlib import Path


INSTALL = 'python -m playwright install --only-shell chromium'


class CaptureError(RuntimeError):
    pass


class ChromiumMissing(CaptureError):
    pass


async def _shoot(browser, html, out, width, height, scale, gate):
    async with gate:
        context = await browser.new_context(viewport={'width': width, 'height': height}, device_scale_factor=scale,
                                            java_script_enabled=False, offline=True)
        try:
            page = await context.new_page()
            await page.route('**/*', lambda route: route.abort() if not route.request.url.startswith('data:')
                             else route.continue_())
            await page.set_content(html, wait_until='load')
            await page.screenshot(path=str(out), full_page=False, animations='disabled')
        finally:
            await context.close()
    return Path(out)


async def _capture(pages, width, height, scale, concurrency):
    from playwright.async_api import async_playwright
    gate = asyncio.Semaphore(concurrency)
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        try:
            return await asyncio.gather(*(_shoot(browser, h, o, width, height, scale, gate) for h, o in pages))
        finally:
            await browser.close()


def capture(pages, width=1920, height=1080, scale=2, concurrency=4):
    if importlib.util.find_spec('playwright') is None:
        raise CaptureError('Playwright for Python is not installed: install the plugin requirements, then run '
                           f'`{INSTALL}`')
    try:
        return asyncio.run(_capture(pages, width, height, scale, concurrency))
    except Exception as e:
        if 'Executable doesn\'t exist' in str(e):
            raise ChromiumMissing(f'Playwright\'s Chromium is missing: run `{INSTALL}`') from e
        raise
