import { DATE_RE, parseUtcDate, pickMode, resolveEffort } from './common.mjs'
import { isPairFailed } from './trials.mjs'

export function publisherToVendor(publisher) {
  const p = publisher.trim().toLowerCase()
  if (p === 'anthropic' || p === 'claude') return 'claude'
  if (p === 'openai' || p === 'codex') return 'codex'
  if (p === 'google' || p === 'google deepmind' || p === 'deepmind' || p === 'gemini' || p === 'antigravity') {
    return 'gemini'
  }
  return p
}

export function isWithinSixMonths(pageDateStr, nowDate) {
  const dt = parseUtcDate(pageDateStr)
  if (!dt) return false
  const cutoffYear = nowDate.getUTCFullYear()
  const cutoffMonth = nowDate.getUTCMonth() - 6
  const cutoffDay = nowDate.getUTCDate()
  const targetYear = cutoffYear + Math.floor(cutoffMonth / 12)
  const targetMonth = ((cutoffMonth % 12) + 12) % 12
  const lastDay = new Date(Date.UTC(targetYear, targetMonth + 1, 0)).getUTCDate()
  const cutoff = new Date(Date.UTC(targetYear, targetMonth, Math.min(cutoffDay, lastDay)))
  const maxAllowed = new Date(nowDate.getTime() + 24 * 60 * 60 * 1000)
  return dt >= cutoff && dt <= maxAllowed
}

export function clusterSources(leadingSources, notes) {
  const n = leadingSources.length
  const parent = Array.from({ length: n }, (_, i) => i)
  const find = (x) => (parent[x] === x ? x : (parent[x] = find(parent[x])))
  const unite = (a, b) => {
    const ra = find(a)
    const rb = find(b)
    if (ra !== rb) parent[rb] = ra
  }

  for (let i = 0; i < n; i++) {
    for (let j = i + 1; j < n; j++) {
      const a = leadingSources[i]
      const b = leadingSources[j]
      const samePub = a.row.publisher.trim().toLowerCase() === b.row.publisher.trim().toLowerCase()
      const sameSet = a.row.task_set.trim().toLowerCase() === b.row.task_set.trim().toLowerCase()
      if (samePub || sameSet) {
        unite(i, j)
        const reasons = []
        if (samePub) reasons.push(`shared publisher '${a.row.publisher}'`)
        if (sameSet) reasons.push(`shared task_set '${a.row.task_set}'`)
        notes.push(`${a.row.id} and ${b.row.id} count as one source (${reasons.join(' and ')})`)
      }
    }
  }

  const groups = new Map()
  for (let i = 0; i < n; i++) {
    const root = find(i)
    if (!groups.has(root)) groups.set(root, [])
    groups.get(root).push(leadingSources[i])
  }
  return [...groups.values()]
}

export function evaluateSources({
  activeRows,
  manifestById,
  recordsBySource,
  modelsByVendor,
  claudeModels,
  skippedSilentVendors,
  unavailableInUseVendors,
  nowDate,
  notes,
}) {
  const sourcesOut = []
  const leadingEvaluations = []

  for (const row of activeRows) {
    const mEntry = manifestById.get(row.id)
    const readState = !mEntry || mEntry.state !== 'read'
      ? 'unread'
      : mEntry.stale === true
        ? 'cached-stale'
        : 'live'
    const pageDate =
      mEntry && typeof mEntry.page_date === 'string' && DATE_RE.test(mEntry.page_date)
        ? mEntry.page_date
        : null
    const ageSeconds = mEntry && typeof mEntry.age_seconds === 'number' ? mEntry.age_seconds : null
    const fetchReason = mEntry && typeof mEntry.reason === 'string' ? mEntry.reason : null

    if (readState === 'unread') {
      const reason = fetchReason || 'missing-from-manifest'
      notes.push(`${row.id}: unread (${reason})`)
      sourcesOut.push({
        source_id: row.id,
        link: row.link,
        publisher: row.publisher,
        task_set: row.task_set,
        status: row.status,
        provider_own: row.provider_own,
        read: 'unread',
        page_date: null,
        age_seconds: ageSeconds,
        role: 'unread',
        reason,
      })
      continue
    }

    let rawRecords = (recordsBySource.get(row.id) || []).map((r) => ({ ...r }))

    if (row.provider_own) {
      const ownVendor = publisherToVendor(row.publisher)
      const dropped = rawRecords.filter((r) => r.vendor !== ownVendor)
      rawRecords = rawRecords.filter((r) => r.vendor === ownVendor)
      if (dropped.length > 0) {
        notes.push(`${row.id}: provider-own results support only ${ownVendor} models (dropped ${dropped.length} other-vendor record(s))`)
      } else {
        notes.push(`${row.id}: provider-own source is support-only for ${ownVendor}`)
      }
    }

    for (const r of rawRecords) {
      if (r.verdict === 'abstain') continue
      if (skippedSilentVendors.has(r.vendor) || unavailableInUseVendors.has(r.vendor)) {
        r.verdict = 'abstain'
        continue
      }
      const vInfo = modelsByVendor.get(r.vendor)
      if (!vInfo) {
        notes.push(`${row.id}: abstains for ${r.vendor} (not a candidate vendor in --models)`)
        r.verdict = 'abstain'
        continue
      }
      if (vInfo.status !== 'ok' || vInfo.ids.length === 0) {
        r.verdict = 'abstain'
        continue
      }
      if (!r.model || !vInfo.idSet.has(r.model.toLowerCase())) {
        notes.push(
          `${row.id}: abstains for ${r.vendor} (model '${r.model ?? 'none'}' is not in current models)`,
        )
        r.verdict = 'abstain'
      }
    }

    const claudeTested =
      !claudeModels ||
      claudeModels.ids.length === 0 ||
      rawRecords.some((r) => r.vendor === 'claude' && r.verdict !== 'abstain')

    let role = 'support-only'
    let reason = null
    let outcome = null

    if (readState === 'cached-stale') {
      role = 'support-only'
      reason = `stale cache (age ${ageSeconds ?? 'unknown'}s${fetchReason ? `, ${fetchReason}` : ''})`
      notes.push(`${row.id}: cached copy is stale (${reason}); support-only`)
    } else if (!pageDate) {
      role = 'ineligible'
      reason = 'undated'
      notes.push(`${row.id}: no page_date found; ineligible`)
    } else if (!isWithinSixMonths(pageDate, nowDate)) {
      role = 'ineligible'
      reason = `outdated (${pageDate}, older than 6 months)`
      notes.push(`${row.id}: page_date ${pageDate} is older than 6 months; ineligible`)
    } else if (row.status === 'support-only') {
      role = 'support-only'
      reason = 'new source (status support-only)'
    } else if (row.provider_own) {
      role = 'support-only'
      reason = 'provider-own'
    } else if (!claudeTested) {
      role = 'abstains'
      reason = 'abstains for claude (current model not tested)'
      notes.push(`${row.id}: abstains for claude (current model not tested)`)
    } else {
      const leads = rawRecords.filter((r) => r.verdict === 'lead' && r.error_range === true)
      const ties = rawRecords.filter((r) => r.verdict === 'tie' && r.error_range === true)
      const noErrLeadOrTie = rawRecords.filter(
        (r) => (r.verdict === 'lead' || r.verdict === 'tie') && r.error_range === false,
      )
      if (leads.length === 1) {
        role = 'leading'
        outcome = { kind: 'lead', vendor: leads[0].vendor, record: leads[0], records: rawRecords }
      } else if (leads.length === 0 && ties.length >= 2) {
        const tieVendors = [...new Set(ties.map((r) => r.vendor))].sort()
        if (tieVendors.length >= 2) {
          role = 'leading'
          outcome = { kind: 'tie', vendors: tieVendors, records: rawRecords }
        } else {
          role = 'support-only'
          reason = 'no distinct tied vendors'
        }
      } else if (noErrLeadOrTie.length > 0) {
        role = 'support-only'
        reason = 'no error range'
        notes.push(`${row.id}: score has no error_range; support-only`)
      } else {
        role = 'abstains'
        reason = 'no qualifying lead or tie'
      }
    }

    sourcesOut.push({
      source_id: row.id,
      link: row.link,
      publisher: row.publisher,
      task_set: row.task_set,
      status: row.status,
      provider_own: row.provider_own,
      read: readState,
      page_date: pageDate,
      age_seconds: ageSeconds,
      role,
      reason,
    })

    if (role === 'leading' && outcome) {
      leadingEvaluations.push({ row, outcome })
    }
  }

  return { sourcesOut, leadingEvaluations }
}

export function resolveConsensus({
  clusters,
  leadingEvaluations,
  modelsByVendor,
  failedOutcomes,
  claudeDefaultModel,
  claudeVersion,
  claudeEffort,
  effectiveVendorOrder,
  effectiveTiebreak,
  taskType,
  notes,
}) {
  let tiesOut = []
  let resolved = null

  const clusterOutcomes = clusters.map((group) => {
    const first = group[0].outcome
    if (first.kind === 'lead') {
      const allSame = group.every((g) => g.outcome.kind === 'lead' && g.outcome.vendor === first.vendor)
      return allSame ? { kind: 'lead', vendor: first.vendor, group } : { kind: 'split', group }
    }
    const key = first.vendors.join(',')
    const allSame = group.every((g) => g.outcome.kind === 'tie' && g.outcome.vendors.join(',') === key)
    return allSame ? { kind: 'tie', vendors: first.vendors, group } : { kind: 'split', group }
  })

  const allLeads = clusterOutcomes.every((c) => c.kind === 'lead')
  const allTies = clusterOutcomes.every((c) => c.kind === 'tie')

  if (allLeads) {
    const leadVendors = new Set(clusterOutcomes.map((c) => c.vendor))
    if (leadVendors.size === 1) {
      const winner = [...leadVendors][0]
      if (winner === 'claude') {
        resolved = {
          vendor: 'claude',
          model: claudeDefaultModel,
          version: claudeVersion,
          effort: claudeEffort,
          basis: 'consensus',
        }
      } else {
        const winnerRecs = leadingEvaluations
          .map((e) => e.outcome.record)
          .filter((r) => r && r.vendor === winner)
        const vInfo = modelsByVendor.get(winner)
        const rawModel = pickMode(winnerRecs.map((r) => r.model))
        const canonicalModel =
          rawModel && vInfo && vInfo.idCanonical.get(rawModel.toLowerCase())
            ? vInfo.idCanonical.get(rawModel.toLowerCase())
            : rawModel || 'default'
        const rawVersion =
          pickMode(winnerRecs.map((r) => r.version)) ||
          (vInfo && vInfo.versionByModel.get(canonicalModel.toLowerCase())) ||
          null
        const rawEffort = pickMode(winnerRecs.map((r) => r.effort))
        const resolvedEffort = resolveEffort(vInfo, canonicalModel, rawEffort)
        if (
          isPairFailed(failedOutcomes, {
            vendor: winner,
            model: canonicalModel,
            version: rawVersion,
            effort: resolvedEffort,
          })
        ) {
          notes.push(
            `${winner} ${canonicalModel} @ ${resolvedEffort} excluded: failed trial for ${taskType}`,
          )
        } else {
          resolved = {
            vendor: winner,
            model: canonicalModel,
            version: rawVersion || '1',
            effort: resolvedEffort,
            basis: 'consensus',
          }
        }
      }
    } else {
      notes.push(
        `no consensus across ${clusters.length} independent sources (${[...leadVendors].join(' vs ')}); keeping default claude`,
      )
    }
  } else if (allTies) {
    let common = new Set(clusterOutcomes[0].vendors)
    for (const co of clusterOutcomes.slice(1)) {
      common = new Set([...common].filter((v) => co.vendors.includes(v)))
    }
    const tiedVendors = [...common].sort()
    if (tiedVendors.length >= 2) {
      const rawTies = tiedVendors.map((v) => {
        const vRecs = leadingEvaluations
          .flatMap((e) => e.outcome.records)
          .filter((r) => r.vendor === v && r.verdict === 'tie')
        const vInfo = modelsByVendor.get(v)
        const rawModel = pickMode(vRecs.map((r) => r.model))
        const canonicalModel =
          rawModel && vInfo && vInfo.idCanonical.get(rawModel.toLowerCase())
            ? vInfo.idCanonical.get(rawModel.toLowerCase())
            : rawModel || (v === 'claude' ? claudeDefaultModel : 'default')
        const rawVersion =
          pickMode(vRecs.map((r) => r.version)) ||
          (vInfo && vInfo.versionByModel.get(canonicalModel.toLowerCase())) ||
          null
        const rawEffort = pickMode(vRecs.map((r) => r.effort))
        const tokens = vRecs
          .filter((r) => r.tokens)
          .map((r) => ({ ...r.tokens, source_id: r.source_id }))
        return {
          vendor: v,
          model: canonicalModel,
          version: rawVersion,
          effort: v === 'claude' ? claudeEffort : resolveEffort(vInfo, canonicalModel, rawEffort),
          tokens,
        }
      })

      const eligibleTies = []
      for (const t of rawTies) {
        if (t.vendor !== 'claude' && isPairFailed(failedOutcomes, t)) {
          notes.push(`${t.vendor} ${t.model} @ ${t.effort} excluded: failed trial for ${taskType}`)
          continue
        }
        eligibleTies.push(t)
      }
      tiesOut = eligibleTies.map(({ vendor: tv, model: tm, effort: te, tokens: tt }) => ({
        vendor: tv,
        model: tm,
        effort: te,
        tokens: tt,
      }))

      let picked = null
      if (eligibleTies.length >= 2) {
        const eligibleVendors = eligibleTies.map((t) => t.vendor)
        for (const step of effectiveTiebreak) {
          if (step === 'fewest-tokens') {
            const units = new Set(eligibleTies.flatMap((t) => t.tokens.map((x) => x.unit)))
            const allHaveTokens = eligibleTies.every((t) => t.tokens.length > 0)
            if (allHaveTokens && units.size === 1) {
              const scored = eligibleTies
                .map((t) => ({
                  entry: t,
                  avg: t.tokens.reduce((s, x) => s + x.value, 0) / t.tokens.length,
                }))
                .sort((a, b) => a.avg - b.avg)
              if (scored[0].avg < scored[1].avg) {
                picked = scored[0].entry
                notes.push(`tiebreak fewest-tokens selected ${picked.vendor} (${scored[0].avg} ${[...units][0]})`)
                break
              }
            } else {
              notes.push('tiebreak fewest-tokens skipped: tied vendors lack comparable token counts')
            }
          } else if (step === 'most-usage-left') {
            notes.push('tiebreak most-usage-left unavailable: falling back to next tiebreak step')
          } else if (step === 'vendor-order') {
            const ordered = effectiveVendorOrder.find((v) => eligibleVendors.includes(v))
            if (ordered) {
              picked = eligibleTies.find((t) => t.vendor === ordered)
              notes.push(`tiebreak vendor-order selected ${picked.vendor}`)
              break
            }
          }
        }
      } else if (eligibleTies.length === 1 && eligibleTies[0].vendor !== 'claude') {
        picked = eligibleTies[0]
      }

      if (picked) {
        resolved = {
          vendor: picked.vendor,
          model: picked.vendor === 'claude' ? claudeDefaultModel : picked.model,
          version: picked.version || '1',
          effort: picked.effort,
          basis: 'consensus',
        }
      } else {
        notes.push('tie across independent sources with no resolving tiebreak; caller keeps default vendor claude')
      }
    } else {
      notes.push('no overlapping tied vendors across independent sources; keeping default claude')
    }
  } else {
    notes.push('independent sources disagree (mixed lead/tie/split); keeping default claude')
  }

  return { resolved, tiesOut }
}
