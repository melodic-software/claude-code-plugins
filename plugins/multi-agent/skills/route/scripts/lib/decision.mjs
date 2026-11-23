import { raiseEffort } from './common.mjs'
import {
  loadBoundRecords,
  loadManifest,
  mergeTeamRegistryRows,
  normalizeModels,
  readJson,
  validateRegistry,
} from './inputs.mjs'
import {
  isPairFailed,
  loadOutcomesForWorkType,
  resolveOutcomesDir,
  selectActiveTrial,
  selectProvenOutcome,
} from './trials.mjs'
import { clusterSources, evaluateSources, resolveConsensus } from './trust-model.mjs'

export function computeEffectiveVendorOrder(opts, settings) {
  if (opts.vendorOrderSet) return opts.vendorOrder
  const baseOrder = ['claude', 'codex', 'gemini']
  const ranked = baseOrder.map((v, idx) => ({
    v,
    rank: settings.vendors[v] ? settings.vendors[v].rank : null,
    idx,
  }))
  if (ranked.some((x) => x.rank !== null)) {
    ranked.sort((a, b) => {
      if (a.rank !== null && b.rank !== null) return a.rank - b.rank || a.idx - b.idx
      if (a.rank !== null) return -1
      if (b.rank !== null) return 1
      return a.idx - b.idx
    })
    return ranked.map((x) => x.v)
  }
  return opts.vendorOrder
}

export function buildRoutingOffDecision(taskType) {
  return {
    work_type: taskType,
    vendor: null,
    model: null,
    effort: null,
    basis: 'routing-off',
    pair_key: null,
    sources: [],
    ties: [],
    notes: ['routing is off; no recommendation made (trials paused, trial data kept)'],
  }
}

function resolveVendorAvailability(settings, modelsByVendor, notes) {
  const skippedSilentVendors = new Set()
  const unavailableInUseVendors = new Set()
  for (const [vName, cfg] of Object.entries(settings.vendors)) {
    if (cfg.in_use === false) {
      skippedSilentVendors.add(vName)
      continue
    }
    if (cfg.in_use === true) {
      const vInfo = modelsByVendor.get(vName)
      if (!vInfo || vInfo.status !== 'ok' || vInfo.ids.length === 0) {
        unavailableInUseVendors.add(vName)
        const why =
          vInfo && vInfo.reason
            ? vInfo.reason
            : vInfo && vInfo.status !== 'ok'
              ? `status ${vInfo.status}`
              : 'not listed in --models'
        notes.push(`${vName}: declared in use but unavailable (${why})`)
      }
    }
  }
  return { skippedSilentVendors, unavailableInUseVendors }
}

function filterActiveRows(mergedRows, settings, taskType) {
  const rowById = new Map()
  const disabledRows = new Set()
  const activeRows = []
  for (const row of mergedRows) {
    rowById.set(row.id, row)
    const sourceOverride = settings.sources[row.id]
    const isEnabled =
      sourceOverride && typeof sourceOverride.enabled === 'boolean'
        ? sourceOverride.enabled
        : row.enabled !== false
    if (!isEnabled) {
      disabledRows.add(row.id)
      continue
    }
    if (row.workloads.includes(taskType)) {
      activeRows.push(row)
    }
  }
  return { rowById, disabledRows, activeRows }
}

function selectClaudeCannotImage({
  modelsByVendor,
  skippedSilentVendors,
  failedOutcomes,
  taskType,
  notes,
}) {
  let anyFailedImage = false
  let chosen = null
  for (const [v, info] of modelsByVendor.entries()) {
    if (v === 'claude' || skippedSilentVendors.has(v) || info.status !== 'ok' || info.image !== true) {
      continue
    }
    const candModel = info.defaultModel || info.ids[0] || 'default'
    const candVersion = info.versionByModel.get(candModel.toLowerCase()) || null
    const candEffort = info.defaultEffort || 'default'
    if (isPairFailed(failedOutcomes, { vendor: v, model: candModel, version: candVersion, effort: candEffort })) {
      anyFailedImage = true
      notes.push(`${v} ${candModel} @ ${candEffort} excluded: failed trial for ${taskType}`)
      continue
    }
    chosen = {
      vendor: v,
      model: candModel,
      version: candVersion || '1',
      effort: candEffort,
      basis: 'claude-cannot',
    }
    break
  }
  if (!chosen && anyFailedImage) {
    notes.push(`every image-capable vendor failed trial for ${taskType}; user chooses`)
  }
  return chosen
}

export function assembleDecision({ opts, defaults, settings, nowDate, pluginRoot }) {
  const registry = validateRegistry(readJson(opts.registry, 'registry'))
  const manifestById = loadManifest(opts.manifest)
  const modelsByVendor = normalizeModels(readJson(opts.models, 'models'))

  const notes = []
  const mergedRows = mergeTeamRegistryRows(registry, opts.registry, notes)

  if (settings.trials && (settings.trials_prove === null || settings.trials_fail === null)) {
    notes.push('trials switch is on, but trials_prove and trials_fail must both be set; trials stay inactive')
  }

  const { skippedSilentVendors, unavailableInUseVendors } = resolveVendorAvailability(
    settings,
    modelsByVendor,
    notes,
  )
  const { rowById, disabledRows, activeRows } = filterActiveRows(mergedRows, settings, opts.taskType)
  const recordsBySource = loadBoundRecords(
    opts.records,
    disabledRows,
    manifestById,
    rowById,
    opts.taskType,
    notes,
  )

  const claudeModels = modelsByVendor.get('claude')
  const claudeDefaultModel = (claudeModels && claudeModels.defaultModel) || defaults.model
  const claudeBaseEffort = (claudeModels && claudeModels.defaultEffort) || defaults.effort
  const claudeEffort = opts.taskClass === 'heavy' ? raiseEffort(claudeBaseEffort) : claudeBaseEffort
  const claudeVersion =
    (claudeModels && claudeModels.versionByModel.get(claudeDefaultModel.toLowerCase())) || '1'

  const { sourcesOut, leadingEvaluations } = evaluateSources({
    activeRows,
    manifestById,
    recordsBySource,
    modelsByVendor,
    claudeModels,
    skippedSilentVendors,
    unavailableInUseVendors,
    nowDate,
    notes,
  })

  const outcomesDir = resolveOutcomesDir(opts.stateDir, process.env, pluginRoot)
  const { proven: provenOutcomes, failed: failedOutcomes } = loadOutcomesForWorkType(
    outcomesDir,
    opts.taskType,
  )
  const effectiveVendorOrder = computeEffectiveVendorOrder(opts, settings)
  const trialsActive =
    settings.trials && settings.trials_prove !== null && settings.trials_fail !== null

  let vendor = 'claude'
  let model = claudeDefaultModel
  let version = claudeVersion
  let effort = claudeEffort
  let basis = 'default'
  let tiesOut = []

  const provenPick = selectProvenOutcome({
    provenOutcomes,
    modelsByVendor,
    skippedSilentVendors,
    unavailableInUseVendors,
    effectiveVendorOrder,
    taskType: opts.taskType,
    notes,
  })
  if (provenPick) {
    vendor = provenPick.vendor
    model = provenPick.model
    version = provenPick.version
    effort = provenPick.effort
    basis = provenPick.basis
  }

  if (basis === 'default' && opts.taskType === 'image' && claudeModels && claudeModels.image === false) {
    const imagePick = selectClaudeCannotImage({
      modelsByVendor,
      skippedSilentVendors,
      failedOutcomes,
      taskType: opts.taskType,
      notes,
    })
    if (imagePick) {
      vendor = imagePick.vendor
      model = imagePick.model
      version = imagePick.version
      effort = imagePick.effort
      basis = imagePick.basis
    }
  }

  const clusters = clusterSources(leadingEvaluations, notes)
  if (basis === 'default' && clusters.length >= 2) {
    const effectiveTiebreak = opts.tiebreakSet ? opts.tiebreak : settings.tiebreak
    const consensus = resolveConsensus({
      clusters,
      leadingEvaluations,
      modelsByVendor,
      failedOutcomes,
      claudeDefaultModel,
      claudeVersion,
      claudeEffort,
      effectiveVendorOrder,
      effectiveTiebreak,
      taskType: opts.taskType,
      notes,
    })
    tiesOut = consensus.tiesOut
    if (consensus.resolved) {
      vendor = consensus.resolved.vendor
      model = consensus.resolved.model
      version = consensus.resolved.version
      effort = consensus.resolved.effort
      basis = consensus.resolved.basis
    }
  }

  if (basis === 'default' && trialsActive) {
    const trialPick = selectActiveTrial({
      recordsBySource,
      modelsByVendor,
      skippedSilentVendors,
      unavailableInUseVendors,
      effectiveVendorOrder,
      failedOutcomes,
      taskType: opts.taskType,
      taskClass: opts.taskClass,
      notes,
    })
    if (trialPick) {
      vendor = trialPick.vendor
      model = trialPick.model
      version = trialPick.version
      effort = trialPick.effort
      basis = trialPick.basis
    }
  } else if (basis === 'default' && clusters.length < 2) {
    notes.push(
      `fewer than 2 independent leading sources (${clusters.length}); keeping default claude`,
    )
  }

  return {
    work_type: opts.taskType,
    vendor,
    model,
    effort,
    basis,
    pair_key: `${vendor}:${model}:${version}:${effort}:${opts.taskType}`,
    sources: sourcesOut,
    ties: tiesOut,
    notes,
  }
}
