import { execFileSync } from 'node:child_process'
import {
  accessSync,
  closeSync,
  constants,
  fstatSync,
  lstatSync,
  openSync,
  readdirSync,
  readFileSync,
  realpathSync,
  statSync,
} from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

const MANAGED_DIRS = {
  darwin: '/Library/Application Support/ClaudeCode',
  linux: '/etc/claude-code',
  win32: 'C:/Program Files/ClaudeCode',
}

const PLUGIN_RE = /^[A-Za-z0-9][A-Za-z0-9._-]*$/
const KEY_RE = /^[a-z][a-z0-9_]*_enabled$/
const CONVENTION_HOME_BEGIN = '<!-- BEGIN GENERATED: convention-home -->'
const CONVENTION_HOME_END = '<!-- END GENERATED: convention-home -->'
const CONVENTION_HOME_MAX_LINE = 4096
const CONVENTION_HOME_SEG_RE = /^[A-Za-z0-9._-]+$/

const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value)

function toPosix(raw) {
  let p = String(raw ?? '').replaceAll('\\', '/')
  const m = /^([A-Za-z]):(\/.*)?$/.exec(p)
  if (m) p = `/${m[1].toLowerCase()}${m[2] ?? ''}`
  return p.length > 1 ? p.replace(/\/+$/, '') : p
}

export function isNoRepositoryLayer(root, homeDir) {
  const normRoot = toPosix(root)
  const normHome = toPosix(homeDir)
  if (!normRoot) return true
  if (!normHome) return false
  return normRoot === normHome || `${normHome}/`.startsWith(`${normRoot}/`)
}

function reportDropped(key, value, source, writeErr) {
  const shown = value.length <= 60 ? value : `${value.slice(0, 60)}...`
  writeErr(`hook-enabled: ${key}: dropped "${shown}" from ${source}; only an unquoted true or false is read`)
}

function resolveInstall(sourceFile) {
  const norm = String(sourceFile ?? '').replaceAll('\\', '/')
  if (!norm.startsWith('/') && !/^[A-Za-z]:\//.test(norm)) return null
  const marker = '/plugins/cache/'
  const idx = norm.lastIndexOf(marker)
  if (idx < 0) return null
  const rest = norm.slice(idx + marker.length).split('/')
  if (rest.length < 4 || !rest[0] || !rest[1]) return null
  const [marketplace, name] = rest
  const prefix = norm.slice(0, idx) || '/'
  return { id: `${name}@${marketplace}`, settingsFile: `${prefix}/settings.json` }
}

function userSettingsFile(env) {
  const dir = env.CLAUDE_CONFIG_DIR || (env.HOME ? `${env.HOME}/.claude` : '')
  if (!dir) return null
  return `${dir.replaceAll('\\', '/').replace(/\/+$/, '')}/settings.json`
}

function defaultManagedFiles(platform) {
  const dir = MANAGED_DIRS[platform]
  if (!dir) return []
  const files = []
  const primary = `${dir}/managed-settings.json`
  try {
    if (statSync(primary).isFile()) files.push(primary)
  } catch {
  }
  const dropinDir = `${dir}/managed-settings.d`
  let names = []
  try {
    names = readdirSync(dropinDir)
  } catch {
  }
  for (const name of names.filter((n) => n.endsWith('.json') && !n.startsWith('.')).sort()) {
    const full = `${dropinDir}/${name}`
    try {
      if (statSync(full).isFile()) files.push(full)
    } catch {
    }
  }
  return files
}

function extractOption(text, key, id, name, from, writeErr) {
  let settings
  try {
    settings = JSON.parse(text)
  } catch {
    return null
  }
  if (!isObject(settings) || !isObject(settings.pluginConfigs)) return null
  const values = new Set()
  for (const [entryKey, entry] of Object.entries(settings.pluginConfigs)) {
    const match = id ? entryKey === id : entryKey.startsWith(`${name}@`)
    if (!match || !isObject(entry) || !isObject(entry.options)) continue
    if (!Object.hasOwn(entry.options, key)) continue
    const raw = entry.options[key]
    if (raw === null || raw === undefined) continue
    if (typeof raw === 'boolean') values.add(String(raw))
    else if (typeof raw === 'string') values.add(raw)
    else values.add(JSON.stringify(raw))
  }
  if (values.size === 0) return null
  if (values.size > 1) {
    writeErr(`hook-enabled: ${key}: skipped ${from}; entries for more than one marketplace set different values`)
    return null
  }
  return [...values][0]
}

function readManagedFile(file, ownerCheck, key, id, name, from, writeErr) {
  let fd
  try {
    fd = openSync(file, 'r')
    const fstat = fstatSync(fd)
    if (!fstat.isFile()) return null
    let trusted = true
    if (ownerCheck) {
      const pstat = lstatSync(file)
      const sameFile = fstat.dev === pstat.dev && fstat.ino === pstat.ino
      const rootOwned = fstat.uid === 0
      const noGroupOrOtherWrite = (fstat.mode & 0o022) === 0
      let writableBySelf = false
      const isRoot = typeof process.geteuid === 'function' && process.geteuid() === 0
      if (!isRoot) {
        try {
          accessSync(file, constants.W_OK)
          writableBySelf = true
        } catch {
          writableBySelf = false
        }
      }
      trusted = sameFile && rootOwned && noGroupOrOtherWrite && !writableBySelf
    }
    const text = readFileSync(fd, 'utf8')
    const value = extractOption(text, key, id, name, from, writeErr)
    if (value === null) return null
    return { value, trusted }
  } catch {
    return null
  } finally {
    if (fd !== undefined) {
      try {
        closeSync(fd)
      } catch {
      }
    }
  }
}

function resolveManagedValue(key, name, sourceFile, platform, managedFilesOpt, ownerCheckOpt, writeErr) {
  let id = ''
  let entryLabel
  if (name) {
    entryLabel = `${name}@*`
  } else {
    const install = resolveInstall(sourceFile)
    if (!install) return null
    id = install.id
    entryLabel = id
  }
  const files = managedFilesOpt ?? defaultManagedFiles(platform)
  const ownerCheck = ownerCheckOpt ?? platform === 'linux'
  let resolved = null
  for (const file of files) {
    const from = `pluginConfigs["${entryLabel}"] in ${file}`
    const hit = readManagedFile(file, ownerCheck, key, id, name, from, writeErr)
    if (!hit) continue
    if (hit.value === 'true') {
      resolved = 'true'
    } else if (hit.value === 'false') {
      if (!hit.trusted) {
        writeErr(
          `hook-enabled: ${key}: skipped false from ${file}; a managed file that turns a guard off must be root-owned and writable by no one else`,
        )
        continue
      }
      resolved = 'false'
    } else {
      reportDropped(key, hit.value, from, writeErr)
    }
  }
  return resolved
}

function resolveSettingsValue(key, name, sourceFile, env, writeErr) {
  let id = ''
  let file
  let from
  if (name) {
    file = userSettingsFile(env)
    if (!file) return null
    from = `pluginConfigs["${name}@*"] in ${file}`
  } else {
    const install = resolveInstall(sourceFile)
    if (!install) return null
    id = install.id
    file = install.settingsFile
    from = `pluginConfigs["${id}"] in ${file}`
  }
  let text
  try {
    if (!statSync(file).isFile()) return null
    text = readFileSync(file, 'utf8')
  } catch {
    return null
  }
  const value = extractOption(text, key, id, name, from, writeErr)
  if (value === null) return null
  return { value, from }
}

function readRepoValue(file, key, writeErr) {
  let st
  try {
    st = lstatSync(file)
  } catch {
    return undefined
  }
  if (st.isSymbolicLink()) {
    writeErr(`hook-enabled: ${key}: skipped ${file}; a symlink, and the repository layer reads only regular files`)
    return undefined
  }
  if (!st.isFile()) return undefined
  let text
  try {
    text = readFileSync(file, 'utf8')
  } catch {
    return undefined
  }
  if (text.startsWith('\uFEFF')) text = text.slice(1)
  const prefix = `${key}:`
  for (const rawLine of text.split('\n')) {
    if (!rawLine.startsWith(prefix)) continue
    let val = rawLine.slice(prefix.length)
    if (val.endsWith('\r')) val = val.slice(0, -1)
    const hashIdx = val.indexOf('#')
    if (hashIdx >= 0) val = val.slice(0, hashIdx)
    return val.trim()
  }
  return undefined
}

function trimConventionLine(raw) {
  let s = raw.endsWith('\r') ? raw.slice(0, -1) : raw
  if (s.length > CONVENTION_HOME_MAX_LINE) s = s.slice(0, CONVENTION_HOME_MAX_LINE)
  if (s.startsWith('\uFEFF')) s = s.slice(1)
  return s.trim()
}

function isPureAgentsShim(text) {
  let seen = false
  for (const rawLine of text.split('\n')) {
    const trimmed = trimConventionLine(rawLine)
    if (!trimmed) continue
    if (trimmed !== '@AGENTS.md') return false
    seen = true
  }
  return seen
}

function scanConventionHome(text) {
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

function isValidConventionHome(token) {
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

function readRegularFile(path) {
  try {
    if (!statSync(path).isFile()) return null
    return readFileSync(path, 'utf8')
  } catch {
    return null
  }
}

export function resolveConventionHome(root) {
  if (!root) return 'docs/conventions'
  const agentsPath = join(root, 'AGENTS.md')
  const claudePath = join(root, 'CLAUDE.md')
  const agentsText = readRegularFile(agentsPath)
  let claudeText = readRegularFile(claudePath)
  if (agentsText !== null && claudeText !== null) {
    try {
      if (realpathSync(agentsPath) === realpathSync(claudePath)) claudeText = null
    } catch {
    }
  }
  const agentsScan = agentsText !== null ? scanConventionHome(agentsText) : { state: 'none', token: '' }
  let claudeScan = { state: 'none', token: '' }
  if (claudeText !== null && !isPureAgentsShim(claudeText)) {
    claudeScan = scanConventionHome(claudeText)
  }
  const chosen = agentsScan.state !== 'none' ? agentsScan : claudeScan
  if (chosen.state === 'none' || chosen.state === 'empty') return 'docs/conventions'
  if (chosen.state !== 'one') return null
  if (!isValidConventionHome(chosen.token)) return null
  const homeDir = chosen.token.replace(/\/+$/, '')
  const target = join(root, homeDir)
  try {
    if (!statSync(target).isDirectory()) return null
    const physRoot = toPosix(realpathSync(root))
    const physTarget = toPosix(realpathSync(target))
    const expected = physRoot === '/' ? `/${homeDir}` : `${physRoot}/${homeDir}`
    if (physTarget !== expected) return null
    return homeDir
  } catch {
    return null
  }
}

function gitTopLevel(cwd, env) {
  try {
    return execFileSync('git', ['rev-parse', '--show-toplevel'], {
      cwd,
      env,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim()
  } catch {
    return ''
  }
}

export function resolveHookEnabled(plugin, key, defaultValue, opts = {}) {
  const writeErr = opts.stderr ?? ((msg) => process.stderr.write(`${msg}\n`))
  if (typeof plugin !== 'string' || !PLUGIN_RE.test(plugin)) {
    writeErr(`hook-enabled: plugin name "${plugin}" is not a plain name`)
    return 2
  }
  if (typeof key !== 'string' || !KEY_RE.test(key)) {
    writeErr(`hook-enabled: key "${key}" is not a snake_case <name>_enabled key`)
    return 2
  }
  if (typeof defaultValue !== 'boolean') {
    writeErr(`hook-enabled: ${key}: plugin default "${defaultValue}" is not true or false`)
    return 2
  }

  const security = Boolean(opts.security)
  const gitHook = Boolean(opts.gitHook)
  const env = opts.env ?? process.env
  const platform = opts.platform ?? process.platform
  const sourceFile = opts.sourceFile ?? fileURLToPath(import.meta.url)
  const name = gitHook ? plugin : ''

  let root = opts.root
  if (root === undefined) {
    root = gitHook ? gitTopLevel(opts.cwd ?? process.cwd(), env) : env.CLAUDE_PROJECT_DIR ?? ''
  }

  if (security) {
    const managed = resolveManagedValue(key, name, sourceFile, platform, opts.managedFiles, opts.ownerCheck, writeErr)
    if (managed !== null) return managed === 'true' ? 0 : 1
  }

  if (security || gitHook) {
    const setting = resolveSettingsValue(key, name, sourceFile, env, writeErr)
    if (setting !== null) {
      if (setting.value === 'true') return 0
      if (setting.value === 'false') return 1
      reportDropped(key, setting.value, setting.from, writeErr)
    }
  }

  if (!gitHook) {
    const optionName = `CLAUDE_PLUGIN_OPTION_${key.toUpperCase()}`
    const userVal = env[optionName] ?? ''
    if (userVal === 'true') return 0
    if (userVal === 'false') {
      if (!security) return 1
    } else if (userVal !== '') {
      reportDropped(key, userVal, optionName, writeErr)
    }
  }

  if (!isNoRepositoryLayer(root, env.HOME ?? '')) {
    const home = opts.home !== undefined ? opts.home : resolveConventionHome(root)
    if (home !== null) {
      const file = join(root, home, `${plugin}.yaml`)
      const repoVal = readRepoValue(file, key, writeErr)
      if (repoVal !== undefined) {
        if (repoVal === 'true') return 0
        if (repoVal === 'false') {
          if (!security) return 1
        } else {
          reportDropped(key, repoVal, file, writeErr)
        }
      }
    }
  }

  return defaultValue ? 0 : 1
}

export function isHookEnabled(plugin, key, defaultValue, opts = {}) {
  return resolveHookEnabled(plugin, key, defaultValue, opts) !== 1
}
