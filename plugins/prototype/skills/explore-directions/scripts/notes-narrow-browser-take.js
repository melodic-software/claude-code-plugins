async page => {
  const R = [], ok = (name, pass, detail) => R.push((pass ? "PASS " : "FAIL ") + name + (detail !== undefined ? "  [" + detail + "]" : ""));
  try {
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto("http://127.0.0.1:__PORT__/");
    await page.waitForFunction(() => !document.getElementById("pick").disabled, null, { timeout: 10000 });
    const frame = page.frames().find((f) => f !== page.mainFrame());
    const inFrame = page.frameLocator("#page");
    const cell = inFrame.locator('[data-variant="A"] [data-testid="shipments-parcel-row"]').nth(2).locator("td").nth(1);
    await page.click("#pick");
    await cell.click();
    await page.waitForSelector("#composer:not([hidden])", { timeout: 5000 });
    await page.keyboard.insertText("Out for delivery, PT-1003");
    await page.click("#send");
    await page.waitForFunction(() => /Note 1 sent/.test(document.getElementById("status").textContent), null, { timeout: 5000 });

    const overlap = () => frame.evaluate(() => {
      const m = [...document.documentElement.lastElementChild.children].find((e) => !e.style.outline && e.textContent === "1");
      const c = [...document.querySelectorAll('[data-variant="A"] [data-testid="shipments-parcel-row"]')][2].children[1];
      if (!m) return { meets: false, why: "no marker 1" };
      const a = m.getBoundingClientRect(), b = c.getBoundingClientRect();
      const meets = a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top;
      return { meets, marker: [a.left, a.top].map(Math.round).join(","), cell: [b.left, b.top, b.right, b.bottom].map(Math.round).join(",") };
    });
    const meetsSoon = () => frame.waitForFunction(() => {
      const m = [...document.documentElement.lastElementChild.children].find((e) => !e.style.outline && e.textContent === "1");
      const c = [...document.querySelectorAll('[data-variant="A"] [data-testid="shipments-parcel-row"]')][2].children[1];
      if (!m) return false;
      const a = m.getBoundingClientRect(), b = c.getBoundingClientRect();
      return a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top;
    }, null, { timeout: 3000 }).catch(() => {});
    await meetsSoon();
    const wide = await overlap();
    ok("at 1440px note 1's marker overlaps the PT-1003 status cell it was made on", wide.meets, JSON.stringify(wide));
    await page.setViewportSize({ width: 390, height: 844 });
    await meetsSoon();
    const narrow = await overlap();
    ok("after the frame narrows to 390px note 1's marker still overlaps the PT-1003 status cell", narrow.meets, JSON.stringify(narrow));

    const tools = () => page.evaluate(() => [...document.querySelectorAll("#bar > button, #bar > .wrap > button")]
      .filter((b) => b.checkVisibility() && !b.dataset.edge)
      .map((b) => {
        const r = b.getBoundingClientRect(), x = r.left + r.width / 2, y = r.top + r.height / 2;
        const side = r.left < 0 ? "start" : r.right > innerWidth ? "end" : "";
        return { id: b.id, side, disabled: b.disabled, hit: !side && document.elementFromPoint(x, y)?.closest("button") === b };
      }));
    const cue = (side) => page.evaluate((side) => {
      const c = document.querySelector(`#bar [data-edge="${side}"]`);
      if (!c || !c.checkVisibility({ visibilityProperty: true, opacityProperty: true })) return false;
      const r = c.getBoundingClientRect();
      return r.width > 0 && r.left >= 0 && r.right <= innerWidth && document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2)?.closest("[data-edge]") === c;
    }, side);
    const uncued = async () => {
      const out = [];
      for (const t of await tools()) if (t.side && !(await cue(t.side))) out.push(`${t.id}@${t.side}`);
      return out;
    };
    const luminance = (rgb) => {
      const [r, g, b] = rgb.match(/[\d.]+/g).slice(0, 3).map((v) => {
        const c = Number(v) / 255;
        return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
      });
      return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    };
    const contrast = async (side) => {
      const [fg, bg] = await page.evaluate((side) => {
        const c = document.querySelector(`#bar [data-edge="${side}"]`);
        return c ? [getComputedStyle(c.querySelector("svg")).stroke, getComputedStyle(document.getElementById("bar")).backgroundColor] : ["rgb(0,0,0)", "rgb(0,0,0)"];
      }, side);
      const [a, b] = [luminance(fg), luminance(bg)].sort((x, y) => y - x);
      return (a + 0.05) / (b + 0.05);
    };

    for (const scheme of ["light", "dark"]) {
      await page.emulateMedia({ colorScheme: scheme });
      await page.evaluate(() => { document.getElementById("bar").scrollLeft = 0; });
      await page.waitForTimeout(100);
      const hidden = (await tools()).filter((t) => t.side).map((t) => t.id);
      ok(`${scheme}: at 390px some bar tools sit past the screen's edge, so the bar needs a cue`, hidden.length > 0, hidden.join());
      ok(`${scheme}: every bar tool past the screen's edge has a visible cue on that side`, (await uncued()).length === 0, (await uncued()).join());
      const ratio = await contrast("end");
      ok(`${scheme}: the cue's arrow stands out from the bar at 3:1 or more`, ratio >= 3, ratio.toFixed(2));
    }
    await page.emulateMedia({ colorScheme: "light" });

    await page.evaluate(() => { document.getElementById("bar").scrollLeft = 0; });
    const tapped = new Set();
    for (let i = 0; i < 8; i++) {
      for (const t of await tools()) if (t.hit) tapped.add(t.id);
      if (!(await cue("end"))) break;
      await page.locator('#bar [data-edge="end"]').click();
      await page.waitForTimeout(400);
    }
    const all = (await tools()).filter((t) => !t.disabled).map((t) => t.id);
    const missed = all.filter((id) => !tapped.has(id));
    ok("tapping the end cue brings every enabled tool into view uncovered, Markers, Copy and Notes included", missed.length === 0 && ["markers", "copy-button", "dock"].every((id) => tapped.has(id)), `missed ${missed.join()}`);
    const startCue = await cue("start");
    ok("at the bar's end the start cue shows, to scroll back", startCue);
    if (startCue) await page.locator('#bar [data-edge="start"]').click();
    await page.waitForTimeout(400);
    ok("tapping the start cue brings Pick back into view", (await tools()).find((t) => t.id === "pick")?.hit === true);

    const focused = () => page.evaluate(() => {
      const b = document.activeElement, r = b.getBoundingClientRect();
      return { id: b.id, inBar: !!b.closest("#bar"), hit: document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2)?.closest("button") === b };
    });
    const walk = async (key, firstId) => {
      const seen = new Map();
      await page.evaluate((id) => document.getElementById(id).focus(), firstId);
      for (let i = 0; i < 20; i++) {
        const f = await focused();
        if (!f.inBar) break;
        seen.set(f.id, f.hit);
        await page.keyboard.press(key);
      }
      return seen;
    };
    const forward = await walk("Tab", "pick"), back = await walk("Shift+Tab", "dock");
    const bad = (seen) => all.filter((id) => seen.get(id) !== true && !(id === "vprev" || id === "vnext" || id === "view")).join();
    ok("Tab from Pick reaches every later tool and scrolls each into view uncovered", bad(forward) === "" && forward.get("dock") === true, bad(forward));
    ok("Shift+Tab from Notes reaches every earlier tool and scrolls each into view uncovered", all.every((id) => back.get(id) === true), all.filter((id) => back.get(id) !== true).join());
  } catch (err) {
    R.push("ERROR " + String(err && err.message || err).slice(0, 300));
  }
  return R.join("\n");
}
