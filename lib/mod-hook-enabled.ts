import type { EngineInterface, PluginOptions } from 'claude-code'

const PLUGIN_RE = /^[A-Za-z0-9][A-Za-z0-9._-]*$/
const KEY_RE = /^[a-z][a-z0-9_]*_enabled$/
const CONVENTION_HOME_BEGIN = '<!-- BEGIN GENERATED: convention-home -->'
const CONVENTION_HOME_END = '<!-- END GENERATED: convention-home -->'
const CONVENTION_HOME_MAX_LINE = 4096
const CONVENTION_HOME_SEG_RE = /^[A-Za-z0-9._-]+$/

export type ModHookEnablementSpec = {
  readonly plugin: string
  readonly key: string
  readonly defaultValue: boolean
  readonly security?: boolean
  readonly home?: string
}

export type ParseResult =
  | { readonly status: 'absent' }
  | { readonly status: 'value'; readonly value: boolean }
  | { readonly status: 'invalid'; readonly raw: string }

export type ModEnablementLog = (message: string) => void

export type ModEnablement = {
  readonly options: PluginOptions
  readonly spec: ModHookEnablementSpec
  readonly isDisabledAtLoad: () => boolean
  readonly isEnabled: () => boolean
  readonly setEnabled: (value: boolean) => void
}

const isObject = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === 'object' && !Array.isArray(value)

function toPosix(raw: string): string {
  let p = raw.replaceAll('\\', '/')
  const drive = /^([A-Za-z]):(\/.*)?$/.exec(p)
  if (drive && drive[1]) p = `/${drive[1].toLowerCase()}${drive[2] ?? ''}`
  return p.length > 1 ? p.replace(/\/+$/, '') : p
}

export function isNoRepositoryLayer(root: string, homeDir: string): boolean {
  const normRoot = toPosix(root)
  const normHome = toPosix(homeDir)
  if (!normRoot) return true
  if (!normHome) return false
  if (normRoot === '/') return normHome.startsWith('/')
  return normRoot === normHome || `${normHome}/`.startsWith(`${normRoot}/`)
}

function droppedMessage(key: string, value: string, source: string): string {
  const shown = value.length <= 60 ? value : `${value.slice(0, 60)}...`
  return `hook-enabled: ${key}: dropped "${shown}" from ${source}; only an unquoted true or false is read`
}

export function resolveInstallId(pluginRoot: string): string | null {
  const norm = pluginRoot.replaceAll('\\', '/')
  if (!norm.startsWith('/') && !/^[A-Za-z]:\//.test(norm)) return null
  const marker = '/plugins/cache/'
  const idx = norm.lastIndexOf(marker)
  if (idx < 0) return null
  const rest = norm.slice(idx + marker.length).split('/')
  if (rest.length < 3 || !rest[0] || !rest[1] || !rest[2]) return null
  return `${rest[1]}@${rest[0]}`
}

export function parseRepoBoolean(text: string, key: string): ParseResult {
  const body = text.startsWith('\uFEFF') ? text.slice(1) : text
  const prefix = `${key}:`
  for (const rawLine of body.split('\n')) {
    if (!rawLine.startsWith(prefix)) continue
    let val = rawLine.slice(prefix.length)
    if (val.endsWith('\r')) val = val.slice(0, -1)
    const hashIdx = val.indexOf('#')
    if (hashIdx >= 0) val = val.slice(0, hashIdx)
    const trimmed = val.trim()
    if (trimmed === 'true') return { status: 'value', value: true }
    if (trimmed === 'false') return { status: 'value', value: false }
    return { status: 'invalid', raw: trimmed }
  }
  return { status: 'absent' }
}

export function extractPluginOption(
  settings: unknown,
  plugin: string,
  key: string,
  installId: string | null,
  sourceLabel: string,
  log: ModEnablementLog,
): ParseResult {
  if (!isObject(settings) || !isObject(settings.pluginConfigs)) return { status: 'absent' }
  const values = new Set<string>()
  for (const [entryKey, entry] of Object.entries(settings.pluginConfigs)) {
    const match =
      installId !== null
        ? entryKey === installId
        : entryKey === plugin || entryKey.startsWith(`${plugin}@`)
    if (!match || !isObject(entry) || !isObject(entry.options)) continue
    if (!Object.hasOwn(entry.options, key)) continue
    const raw = entry.options[key]
    if (raw === null || raw === undefined) continue
    if (typeof raw === 'boolean') values.add(String(raw))
    else if (typeof raw === 'string') values.add(raw)
    else values.add(JSON.stringify(raw))
  }
  if (values.size === 0) return { status: 'absent' }
  if (values.size > 1) {
    log(`hook-enabled: ${key}: skipped ${sourceLabel}; entries for more than one marketplace set different values`)
    return { status: 'absent' }
  }
  const [only] = values
  if (only === undefined) return { status: 'absent' }
  if (only === 'true') return { status: 'value', value: true }
  if (only === 'false') return { status: 'value', value: false }
  return { status: 'invalid', raw: only }
}

function validateSpec(spec: ModHookEnablementSpec): string | null {
  if (typeof spec.plugin !== 'string' || !PLUGIN_RE.test(spec.plugin)) {
    return `hook-enabled: plugin name "${String(spec.plugin)}" is not a plain name`
  }
  if (typeof spec.key !== 'string' || !KEY_RE.test(spec.key)) {
    return `hook-enabled: key "${String(spec.key)}" is not a snake_case <name>_enabled key`
  }
  if (typeof spec.defaultValue !== 'boolean') {
    return `hook-enabled: ${spec.key}: plugin default "${String(spec.defaultValue)}" is not true or false`
  }
  return null
}

function debugLog($: EngineInterface, message: string): void {
  try {
    $.ui.log(message, { to: 'debug' })
  } catch {
  }
}

function trimConventionLine(raw: string): string {
  let s = raw.endsWith('\r') ? raw.slice(0, -1) : raw
  if (s.length > CONVENTION_HOME_MAX_LINE) s = s.slice(0, CONVENTION_HOME_MAX_LINE)
  if (s.startsWith('\uFEFF')) s = s.slice(1)
  return s.trim()
}

function isPureAgentsShim(text: string): boolean {
  let seen = false
  for (const rawLine of text.split('\n')) {
    const trimmed = trimConventionLine(rawLine)
    if (!trimmed) continue
    if (trimmed !== '@AGENTS.md') return false
    seen = true
  }
  return seen
}

function scanConventionHome(text: string): { readonly state: string; readonly token: string } {
  let inRegion = false
  let regions = 0
  let pointers = 0
  let declined = false
  let token = ''
  for (const rawLine of text.split('\n')) {
    let line = rawLine.endsWith('\r') ? rawLine.slice(0, -1) : rawLine
    if (line.length > CONVENTION_HOME_MAX_LINE) line = line.slice(0, CONVENTION_HOME_MAX_LINE)
    const trimmed = trimConventionLine(line)
    if (trimmed === CONVENTION_HOME_BEGIN) {
      if (inRegion) return { state: 'nested', token: '' }
      inRegion = true
      regions += 1
      continue
    }
    if (trimmed === CONVENTION_HOME_END) {
      inRegion = false
      continue
    }
    if (!inRegion) continue
    if (trimmed === 'declined') {
      declined = true
      continue
    }
    const firstTick = line.indexOf('`')
    if (firstTick >= 0) {
      const secondTick = line.indexOf('`', firstTick + 1)
      if (secondTick > firstTick) {
        pointers += 1
        if (pointers === 1) token = line.slice(firstTick + 1, secondTick)
      }
    }
  }
  if (inRegion) return { state: 'unterminated', token: '' }
  if (regions === 0) return { state: 'none', token: '' }
  if (declined && pointers > 0) return { state: 'mixed', token: '' }
  if (declined) return { state: 'declined', token: '' }
  if (pointers === 0) return { state: 'empty', token: '' }
  if (pointers === 1) return { state: 'one', token }
  return { state: 'many', token: '' }
}

function isValidConventionHome(token: string): boolean {
  if (!token || token.startsWith('/') || token.startsWith('~') || token.includes('\\') || token.includes(':')) {
    return false
  }
  const stripped = token.replace(/\/+$/, '')
  if (!stripped) return false
  for (const seg of stripped.split('/')) {
    if (!seg || seg === '.' || seg === '..' || !CONVENTION_HOME_SEG_RE.test(seg)) return false
    const bare = seg.replace(/\.+$/, '')
    if (bare.toLowerCase() === '.git') return false
  }
  return true
}

async function safeStat($: EngineInterface, path: string, resolve = false) {
  try {
    return resolve ? await $.fs.stat(path, { resolve: true }) : await $.fs.stat(path)
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err)
    return msg.includes('no implementation') ? ('unstubbed' as const) : undefined
  }
}

async function readRootFile(
  $: EngineInterface,
  path: string,
): Promise<{ readonly text: string; readonly resolved?: string } | null> {
  const st = await safeStat($, path, true)
  if (st === undefined) return null
  if (st !== 'unstubbed' && st.kind !== 'file') return null
  const text = await $.fs.read(path).catch(() => undefined)
  if (typeof text !== 'string') return null
  return { text, resolved: st !== 'unstubbed' ? st.resolved : undefined }
}

export async function resolveConventionHome($: EngineInterface, root: string): Promise<string | null> {
  const cleanRoot = root.replace(/[\\/]+$/, '')
  if (!cleanRoot) return 'docs/conventions'
  const [agentsFile, claudeFileRaw] = await Promise.all([
    readRootFile($, `${cleanRoot}/AGENTS.md`),
    readRootFile($, `${cleanRoot}/CLAUDE.md`),
  ])
  let claudeFile = claudeFileRaw
  if (
    agentsFile !== null &&
    claudeFile !== null &&
    agentsFile.resolved !== undefined &&
    claudeFile.resolved !== undefined &&
    toPosix(agentsFile.resolved) === toPosix(claudeFile.resolved)
  ) {
    claudeFile = null
  }
  const agentsScan = agentsFile !== null ? scanConventionHome(agentsFile.text) : { state: 'none', token: '' }
  const claudeScan =
    claudeFile !== null && !isPureAgentsShim(claudeFile.text)
      ? scanConventionHome(claudeFile.text)
      : { state: 'none', token: '' }
  const chosen = agentsScan.state !== 'none' ? agentsScan : claudeScan
  if (chosen.state === 'none' || chosen.state === 'empty') return 'docs/conventions'
  if (chosen.state !== 'one' || !isValidConventionHome(chosen.token)) return null
  const homeDir = chosen.token.replace(/\/+$/, '')
  const target = `${cleanRoot}/${homeDir}`
  const [rootStat, targetStat] = await Promise.all([
    safeStat($, cleanRoot, true),
    safeStat($, target, true),
  ])
  if (targetStat === 'unstubbed') return homeDir
  if (targetStat === undefined || targetStat.kind !== 'dir' || targetStat.isLink) return null
  if (rootStat && rootStat !== 'unstubbed' && rootStat.resolved && targetStat.resolved) {
    const physRoot = toPosix(rootStat.resolved)
    const physTarget = toPosix(targetStat.resolved)
    const expected = physRoot === '/' ? `/${homeDir}` : `${physRoot}/${homeDir}`
    if (physTarget !== expected) return null
  }
  return homeDir
}

export async function resolveModHookEnabled(
  $: EngineInterface,
  options: PluginOptions,
  spec: ModHookEnablementSpec,
  projectDir?: string,
  log?: ModEnablementLog,
): Promise<boolean> {
  const emit: ModEnablementLog = log ?? (message => debugLog($, message))
  const usageError = validateSpec(spec)
  if (usageError !== null) {
    emit(usageError)
    return true
  }

  const security = Boolean(spec.security)
  const installId = resolveInstallId($.plugin.root)
  const entryLabel = installId ?? `${spec.plugin}@*`

  const [policy, flag, user] = await Promise.all([
    $.settings.read({ source: 'policy' }).catch(() => undefined),
    $.settings.read({ source: 'flag' }).catch(() => undefined),
    $.settings.read({ source: 'user' }).catch(() => undefined),
  ])
  for (const [source, settings] of [
    ['policy', policy],
    ['flag', flag],
    ['user', user],
  ] as const) {
    if (settings === undefined) continue
    const label = `pluginConfigs["${entryLabel}"] in ${source} settings`
    const parsed = extractPluginOption(settings, spec.plugin, spec.key, installId, label, emit)
    if (parsed.status === 'value') return parsed.value
    if (parsed.status === 'invalid') emit(droppedMessage(spec.key, parsed.raw, label))
  }

  const rawOpt = options[spec.key]
  if (typeof rawOpt === 'boolean') {
    if (rawOpt !== spec.defaultValue) return rawOpt
  } else if (rawOpt !== undefined) {
    emit(droppedMessage(spec.key, String(rawOpt), `options.${spec.key}`))
  }

  const [sessionRoot, homeEnv, userProfile] = await Promise.all([
    $.session.root().catch(() => undefined),
    $.env.get('HOME').catch(() => undefined),
    $.env.get('USERPROFILE').catch(() => undefined),
  ])
  const root = sessionRoot || projectDir || ''
  const homeDir = homeEnv || userProfile || ''

  if (!isNoRepositoryLayer(root, homeDir)) {
    const resolvedHome =
      spec.home !== undefined
        ? spec.home.replace(/^[\\/]+|[\\/]+$/g, '')
        : await resolveConventionHome($, root)
    if (resolvedHome !== null) {
      const cleanRoot = root.replace(/[\\/]+$/, '')
      const file = `${cleanRoot}/${resolvedHome}/${spec.plugin}.yaml`
      let canRead = true
      const st = await safeStat($, file)
      if (st === undefined) {
        canRead = false
      } else if (st !== 'unstubbed') {
        if (st.isLink) {
          emit(`hook-enabled: ${spec.key}: skipped ${file}; a symlink, and the repository layer reads only regular files`)
          canRead = false
        } else if (st.kind !== 'file') {
          canRead = false
        }
      }
      if (canRead) {
        const text = await $.fs.read(file).catch(() => undefined)
        if (typeof text === 'string') {
          const parsed = parseRepoBoolean(text, spec.key)
          if (parsed.status === 'value') {
            if (parsed.value) return true
            if (!security) return false
          } else if (parsed.status === 'invalid') {
            emit(droppedMessage(spec.key, parsed.raw, file))
          }
        }
      }
    }
  }

  return spec.defaultValue
}

export function createModEnablement(options: PluginOptions, spec: ModHookEnablementSpec): ModEnablement {
  const usageError = validateSpec(spec)
  const raw = options[spec.key]
  let enabled = usageError !== null ? true : typeof raw === 'boolean' ? raw : spec.defaultValue
  const disabledAtLoad = usageError === null && !spec.security && spec.defaultValue && raw === false

  return {
    options,
    spec,
    isDisabledAtLoad: () => disabledAtLoad,
    isEnabled: () => enabled,
    setEnabled: (value: boolean) => {
      enabled = value
    },
  }
}

export async function refreshModEnablement(
  $: EngineInterface,
  gate: ModEnablement,
  projectDir?: string,
): Promise<boolean> {
  const next = await resolveModHookEnabled($, gate.options, gate.spec, projectDir)
  gate.setEnabled(next)
  return next
}
