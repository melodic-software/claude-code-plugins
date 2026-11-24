import path from 'node:path'
import { TASK_CLASSES, TIEBREAK_STEPS, WORK_TYPES, die } from './common.mjs'

export function usage() {
  process.stdout.write(
    [
      'Usage: vendor-decide --task-type <coding|web-ui|knowledge|image> [--settings <file>]',
      '                     --manifest <file> --records <[source_id=]file> [--records ...]',
      '                     --models <file> [--usage <file>] [--registry <file>] [--defaults <file>]',
      '                     [--state-dir <dir>] [--task-class <everyday|heavy>]',
      '                     [--needs-tools <tools>] [--use <investigate|task>] [--context <tokens>]',
      '                     [--tiebreak <steps>] [--vendor-order <vendors>] [--now <YYYY-MM-DD>]',
      '',
    ].join('\n'),
  )
}

export function parseArgs(argv, pluginRoot) {
  const opts = {
    taskType: null,
    taskClass: 'everyday',
    manifest: null,
    records: [],
    models: null,
    usage: null,
    settings: null,
    stateDir: null,
    registry: path.join(pluginRoot, 'reference', 'benchmarks.json'),
    defaults: path.join(pluginRoot, 'reference', 'defaults.yaml'),
    needsTools: [],
    use: 'task',
    context: null,
    tiebreak: [],
    tiebreakSet: false,
    vendorOrder: ['claude', 'codex', 'gemini'],
    vendorOrderSet: false,
    now: null,
  }

  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (a === '-h' || a === '--help') {
      usage()
      process.exit(0)
    }
    const needVal = () => {
      if (i + 1 >= argv.length) die(`${a} requires a value`)
      return argv[++i]
    }
    switch (a) {
      case '--task-type':
        opts.taskType = needVal()
        break
      case '--task-class':
        opts.taskClass = needVal()
        break
      case '--manifest':
        opts.manifest = needVal()
        break
      case '--records':
        opts.records.push(needVal())
        break
      case '--models':
        opts.models = needVal()
        break
      case '--usage':
        opts.usage = needVal()
        break
      case '--needs-tools': {
        const raw = needVal()
        opts.needsTools = raw
          ? [...new Set(raw.split(',').map((s) => s.trim().toLowerCase()).filter(Boolean))]
          : []
        break
      }
      case '--use':
        opts.use = needVal()
        if (opts.use !== 'investigate' && opts.use !== 'task') {
          die(`--use must be investigate or task, got '${opts.use}'`)
        }
        break
      case '--context': {
        const raw = needVal()
        const parsed = Number(raw)
        if (!Number.isInteger(parsed) || parsed <= 0) {
          die(`--context must be a positive integer, got '${raw}'`)
        }
        opts.context = parsed
        break
      }
      case '--settings':
        opts.settings = needVal()
        break
      case '--state-dir':
        opts.stateDir = needVal()
        break
      case '--registry':
        opts.registry = needVal()
        break
      case '--defaults':
        opts.defaults = needVal()
        break
      case '--tiebreak': {
        const raw = needVal()
        opts.tiebreakSet = true
        opts.tiebreak = raw
          ? raw
              .split(',')
              .map((s) => s.trim())
              .filter(Boolean)
          : []
        break
      }
      case '--vendor-order': {
        const raw = needVal()
        opts.vendorOrderSet = true
        opts.vendorOrder = raw
          ? raw
              .split(',')
              .map((s) => s.trim().toLowerCase())
              .filter(Boolean)
          : []
        break
      }
      case '--now':
        opts.now = needVal()
        break
      default:
        die(`unknown argument: ${a}`)
    }
  }

  if (!opts.taskType || !WORK_TYPES.has(opts.taskType)) {
    die(`--task-type must be one of ${[...WORK_TYPES].join(', ')}`)
  }
  if (!TASK_CLASSES.has(opts.taskClass)) {
    die(`--task-class must be one of ${[...TASK_CLASSES].join(', ')}`)
  }
  for (const step of opts.tiebreak) {
    if (!TIEBREAK_STEPS.has(step)) {
      die(`unknown tiebreak step '${step}' (allowed: ${[...TIEBREAK_STEPS].join(', ')})`)
    }
  }
  return opts
}
