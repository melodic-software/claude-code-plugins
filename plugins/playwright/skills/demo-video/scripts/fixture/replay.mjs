// Example replay script over the local fixture pages (no network): node ../record.mjs replay.mjs CAPTURE_DIR.
// Each step is one demo.click ... demo.settle; the step ids key the captions in script.json.
export default async (demo) => {
  await demo.goto(new URL('index.html', import.meta.url).href);

  // the shot frames the hero text block: headline through the button
  const hero = demo.union(await demo.boxOf('#hero h1'), await demo.boxOf('#get-started'));
  await demo.click('get-started', '#get-started', { block: hero });
  await demo.page.waitForURL(/docs\.html/);
  await demo.settle('get-started');
  await demo.wait(800);

  await demo.click('search', '#search', { block: '#search-panel' });
  await demo.type('search', '#search', 'trace viewer');
  await demo.settle('search', { box: '#search-panel' });
  await demo.wait(800);

  await demo.click('open-result', '#results a', { block: '#search-panel' });
  await demo.page.waitForURL(/trace\.html/);
  await demo.settle('open-result');
};
