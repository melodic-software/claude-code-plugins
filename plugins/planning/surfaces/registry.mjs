#!/usr/bin/env node
// Surface registry for /planning:interview: one SurfaceEntry per file in entries/, and
// resolveSurface, which picks one. Adding a surface (or a shared-session variant) is adding an
// entry file; the skill names no surface value and reads what the resolution hands it.
//
// SurfaceEntry (default export of each entries/*.mjs):
//   id          registered value, matched against an argument and the settings
//   reportName  the name the offer and notice lines show
//   aliases     optional words that also ask for it (the `share` action, say)
//   onRequest   optional; true keeps it out of the alternatives and the offer line, so only an
//               argument or a setting picks it
//   available(context) -> {ok, reason}   probes PATH only: no network, no process start
//   start(session) -> handle             {read: [plugin-root-relative spokes], rules}; the
//                                        spoke's own command starts any process
//
// Order: an argument (a surface the user asks for in the session), then planning's `surface`
// userConfig, then the plugin.json default. Nothing about rendered-view mediums is read: medium
// never moves the surface.
//
// With the surface unset, one line names the default, the other available surfaces, any
// installed optional planner, and any optional plugin offer (offers/offer-source.mjs).
//
// CLI: node registry.mjs resolve [--surface <userConfig value>] [--argument <word>]
//                                [--data-dir <plugin data>] [--unattended]
//      prints the resolution as one JSON line; `list` prints the entries.
import { accessSync, constants, readFileSync, readdirSync, realpathSync, statSync } from 'node:fs'
import { delimiter, dirname, join } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { findOffers, installedPlugins } from '../offers/offer-source.mjs'

const here = dirname(fileURLToPath(import.meta.url))
export const PLUGIN_ROOT = join(here, '..')
export const ENTRIES_DIR = join(here, 'entries')

const isUnset = v =>
  v === undefined || v === null || String(v).trim() === '' || /^\$\{user_config\.\w+\}$/.test(String(v).trim())

export async function loadEntries(dir = ENTRIES_DIR) {
  const entries = []
  for (const file of readdirSync(dir).filter(f => f.endsWith('.mjs')).sort()) {
    const { default: e } = await import(pathToFileURL(join(dir, file)).href)
    const bad = !e || typeof e.id !== 'string' || typeof e.reportName !== 'string' ||
      typeof e.available !== 'function' || typeof e.start !== 'function'
    if (bad) throw new Error(`${file}: not a SurfaceEntry {id, reportName, available, start}`)
    if (entries.some(x => x.id === e.id)) throw new Error(`${file}: duplicate surface id ${e.id}`)
    entries.push(e)
  }
  return entries
}

export function pluginDefault(root = PLUGIN_ROOT) {
  const manifest = JSON.parse(readFileSync(join(root, '.claude-plugin', 'plugin.json'), 'utf8'))
  return manifest.userConfig.surface.default
}

function onPath(name, env) {
  const exts = process.platform === 'win32' ? ['', '.exe', '.cmd', '.bat'] : ['']
  for (const dir of (env.PATH || '').split(delimiter).filter(Boolean)) {
    for (const ext of exts) {
      const p = join(dir, name + ext)
      try {
        accessSync(p, constants.X_OK)
        const st = statSync(p)
        if (st.isFile() && st.size > 0) return true
      } catch {}
    }
  }
  return false
}

export function probeContext(env = process.env) {
  return { has: name => onPath(name, env), env }
}

export async function resolveSurface(request = {}) {
  const env = request.env ?? process.env
  const entries = request.entries ?? (await loadEntries())
  const context = request.context ?? probeContext(env)
  const notices = []
  const norm = s => String(s).trim().toLowerCase().replace(/[\s_-]+/g, ' ')
  const match = word => entries.find(e => [e.id, e.reportName, ...(e.aliases ?? [])].some(n => norm(n) === norm(word)))
  const sources = [
    ['argument', request.argument],
    ['userConfig', request.userConfig?.surface],
  ]
  let entry
  let decidedBy = 'default'
  for (const [source, value] of sources) {
    if (isUnset(value)) continue
    entry = match(value)
    if (entry) {
      decidedBy = source
      break
    }
    notices.push(`surface ${JSON.stringify(value)} from ${source} is not registered (${entries.map(e => e.id).join(', ')}); ignored`)
  }
  if (!entry) entry = match(request.default ?? pluginDefault())
  if (!entry) throw new Error('the plugin default surface has no registered entry')

  const available = entry.available(context)
  if (!available.ok) notices.push(`${entry.reportName} unavailable: ${available.reason}`)
  const alternatives = entries.filter(e => e !== entry && !e.onRequest && e.available(context).ok)
  const planners = request.planners ?? []
  const offers = request.offers ?? []
  const also = [...alternatives.map(e => e.reportName), ...planners.map(p => `${p.name} planner (${p.invoke})`)]
  const parts = [
    `surface: ${entry.reportName} (default).`,
    also.length > 0 && `Also available: ${also.join(', ')}. Ask for one by name to switch.`,
    ...offers.map(o => `${o.text}.`),
  ].filter(Boolean)
  const line = decidedBy === 'default' && parts.length > 1 ? parts.join(' ') : null
  const handle = entry.start({ decidedBy, available })
  return {
    surface: entry.id,
    reportName: entry.reportName,
    decidedBy,
    available,
    alternatives: alternatives.map(e => e.id),
    read: handle.read ?? [],
    handle,
    line,
    planners,
    offers,
    notices,
  }
}

async function main(argv) {
  const [cmd, ...rest] = argv
  const opts = {}
  for (let i = 0; i < rest.length; i++) {
    if (rest[i] === '--unattended') {
      opts.unattended = true
      continue
    }
    const key = { '--surface': 'surface', '--argument': 'argument', '--data-dir': 'dataDir' }[rest[i]]
    if (!key || rest[i + 1] === undefined) throw new Error(`unknown or incomplete option ${rest[i]}`)
    opts[key] = rest[++i]
  }
  if (cmd === 'list') {
    const entries = await loadEntries()
    console.log(JSON.stringify(entries.map(e => ({ id: e.id, reportName: e.reportName, aliases: e.aliases ?? [] }))))
    return
  }
  if (cmd !== 'resolve') {
    throw new Error('usage: registry.mjs resolve|list [--surface v] [--argument w] [--data-dir d] [--unattended]')
  }
  const request = { argument: opts.argument, userConfig: { surface: opts.surface } }
  let out = await resolveSurface(request)
  // Planners and offers only ride the default's line, so look them up only when it prints.
  if (out.decidedBy === 'default') {
    const found = await findOffers({ installed: installedPlugins(), unattended: opts.unattended, dataDir: opts.dataDir })
    out = await resolveSurface({ ...request, ...found })
  }
  console.log(JSON.stringify(out))
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))) {
  main(process.argv.slice(2)).catch(e => {
    console.error(`surface registry: ${e.message}`)
    process.exit(2)
  })
}
