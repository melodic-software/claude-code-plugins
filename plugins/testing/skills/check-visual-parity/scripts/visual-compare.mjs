// Hashing, the host check and the pixel count for visual-compare.sh, which
// validates every argument and installs the packages before calling this.
//
//   node visual-compare.mjs probe --deps <install dir>
//   node visual-compare.mjs manifest --dir <d> --browser <s> --viewport <WxH> --scale <n> --head <sha>
//   node visual-compare.mjs compare --deps <install dir> --baseline <d> --after <d>
//                                   --tolerance <n> --reason <text> --diff-dir <d>
//
// Exit: 0 done (compare: every image passed), 1 a failing image, 2 an error.
import { createHash } from 'node:crypto';
import { lstatSync, mkdirSync, readdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import os from 'node:os';
import { join, relative, resolve, isAbsolute } from 'node:path';
import { pathToFileURL } from 'node:url';
import { parseArgs } from 'node:util';

// pixelmatch's documented default colour threshold, passed explicitly so the
// report can print the value the count used.
const THRESHOLD = 0.1;
const MANIFEST = 'manifest.json';
const SCHEMA = 'visual-compare-manifest/1';
const HOST_FIELDS = ['os', 'browser', 'viewport', 'scale'];

class Stop extends Error {}
const stop = (msg) => {
  throw new Stop(msg);
};

const sha256 = (file) => createHash('sha256').update(readFileSync(file)).digest('hex');

// The PNG files directly in <dir>, sorted. Any other entry is ignored; a PNG
// that is not a regular file, or whose name holds a control character, stops.
function pngNames(dir) {
  const names = [];
  for (const name of readdirSync(dir)) {
    if (!/\.png$/i.test(name)) continue;
    if (/[\x00-\x1f\x7f]/.test(name)) stop(`${join(dir, name)}: an image name holds a control character`);
    if (!lstatSync(join(dir, name)).isFile()) stop(`${join(dir, name)}: not a regular file`);
    names.push(name);
  }
  return names.sort();
}

async function loadDeps(deps) {
  const req = createRequire(join(resolve(deps), 'package.json'));
  const pm = await import(pathToFileURL(req.resolve('pixelmatch')).href);
  const png = await import(pathToFileURL(req.resolve('pngjs')).href);
  return { pixelmatch: pm.default, PNG: png.PNG ?? png.default.PNG };
}

async function probe(v) {
  const { pixelmatch, PNG } = await loadDeps(v.deps);
  const a = new PNG({ width: 1, height: 1 });
  if (pixelmatch(a.data, a.data, null, 1, 1, { threshold: THRESHOLD }) !== 0) stop('the probe compare failed');
  console.log('ok');
  return 0;
}

function manifest(v) {
  const names = pngNames(v.dir);
  if (names.length === 0) stop(`${v.dir}: no PNG files to record`);
  const doc = {
    schema: SCHEMA,
    os: `${process.platform} ${process.arch} ${os.release()}`,
    browser: v.browser,
    viewport: v.viewport,
    scale: v.scale,
    head: v.head,
    images: Object.fromEntries(names.map((n) => [n, sha256(join(v.dir, n))])),
  };
  try {
    writeFileSync(join(v.dir, MANIFEST), `${JSON.stringify(doc, null, 2)}\n`, { flag: 'wx' });
  } catch (e) {
    stop(`${join(v.dir, MANIFEST)}: ${e.code === 'EEXIST' ? 'exists; a baseline is never rewritten' : e.message}`);
  }
  console.log(`manifest=${join(v.dir, MANIFEST)} images=${names.length}`);
  return 0;
}

// Read <dir>'s manifest and check that its images are exactly the ones on disk,
// byte for byte.
function checked(dir) {
  let doc;
  try {
    doc = JSON.parse(readFileSync(join(dir, MANIFEST), 'utf8'));
  } catch (e) {
    stop(`${join(dir, MANIFEST)}: cannot read it (${e.code ?? e.message}); capture with the manifest subcommand`);
  }
  if (doc?.schema !== SCHEMA || typeof doc.images !== 'object' || doc.images === null) {
    stop(`${join(dir, MANIFEST)}: not a visual-compare manifest`);
  }
  const listed = Object.keys(doc.images).sort();
  const onDisk = pngNames(dir);
  if (listed.join('\n') !== onDisk.join('\n')) {
    stop(`${dir}: the PNG files differ from the ones its manifest lists`);
  }
  for (const name of listed) {
    if (sha256(join(dir, name)) !== doc.images[name]) {
      stop(`${join(dir, name)}: changed after its manifest was written`);
    }
  }
  return doc;
}

const inside = (child, parent) => {
  const r = relative(parent, child);
  return r === '' || (!r.startsWith('..') && !isAbsolute(r));
};

async function compare(v) {
  const tolerance = Number(v.tolerance);
  const base = checked(v.baseline);
  const after = checked(v.after);
  for (const f of HOST_FIELDS) {
    if (base[f] !== after[f]) {
      stop(`the after capture's ${f} (${after[f]}) differs from the baseline's (${base[f]}); compare on the host and settings the baseline was captured with`);
    }
  }
  const diffDir = resolve(v['diff-dir']);
  for (const d of [v.baseline, v.after]) {
    const real = realpathSync(d);
    if (inside(diffDir, real) || inside(diffDir, resolve(d))) stop(`--diff-dir must be outside ${d}`);
  }
  const { pixelmatch, PNG } = await loadDeps(v.deps);
  console.log(`threshold=${THRESHOLD} tolerance=${tolerance} reason=${v.reason}`);
  let failed = false;
  for (const name of Object.keys(base.images).sort()) {
    let differing;
    if (!(name in after.images)) {
      differing = 'missing';
    } else {
      const a = PNG.sync.read(readFileSync(join(v.baseline, name)));
      const b = PNG.sync.read(readFileSync(join(v.after, name)));
      if (a.width !== b.width || a.height !== b.height) {
        differing = 'size';
      } else {
        const out = new PNG({ width: a.width, height: a.height });
        differing = pixelmatch(a.data, b.data, out.data, a.width, a.height, { threshold: THRESHOLD });
        if (differing > 0) {
          mkdirSync(diffDir, { recursive: true });
          writeFileSync(join(diffDir, name), PNG.sync.write(out));
        }
      }
    }
    const pass = typeof differing === 'number' && differing <= tolerance;
    failed ||= !pass;
    console.log(`differing=${differing} tolerance=${tolerance} verdict=${pass ? 'pass' : 'fail'} name=${name}`);
  }
  return failed ? 1 : 0;
}

const COMMANDS = {
  probe: [probe, { deps: { type: 'string' } }],
  manifest: [
    manifest,
    {
      dir: { type: 'string' },
      browser: { type: 'string' },
      viewport: { type: 'string' },
      scale: { type: 'string' },
      head: { type: 'string', default: '' },
    },
  ],
  compare: [
    compare,
    {
      deps: { type: 'string' },
      baseline: { type: 'string' },
      after: { type: 'string' },
      tolerance: { type: 'string' },
      reason: { type: 'string', default: '' },
      'diff-dir': { type: 'string' },
    },
  ],
};

async function main(argv) {
  const entry = COMMANDS[argv[0]];
  if (!entry) stop(`unknown command: ${argv[0] ?? ''}`);
  const [run, options] = entry;
  const { values } = parseArgs({ args: argv.slice(1), options, strict: true });
  for (const [k, o] of Object.entries(options)) {
    if (o.default === undefined && !values[k]) stop(`--${k} is required`);
  }
  return run(values);
}

try {
  process.exitCode = await main(process.argv.slice(2));
} catch (e) {
  console.error(`visual-compare: ${e instanceof Stop ? e.message : e?.message ?? e}`);
  process.exitCode = 2;
}
