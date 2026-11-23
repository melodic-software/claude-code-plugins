export function applyHarnessGating({
  modelsByVendor,
  skippedSilentVendors,
  unavailableInUseVendors,
  needsTools,
  contextTokens,
  notes,
}) {
  const gatedVendors = new Set()
  const requiredTools = Array.isArray(needsTools) ? needsTools : []

  for (const [vName, vInfo] of modelsByVendor.entries()) {
    if (skippedSilentVendors.has(vName) || unavailableInUseVendors.has(vName)) continue

    if (vInfo.breaker && vInfo.breaker.open === true) {
      gatedVendors.add(vName)
      const reasonPart = vInfo.breaker.reason ? `, ${vInfo.breaker.reason}` : ''
      const resetPart = vInfo.breaker.reset_at ? `reset_at ${vInfo.breaker.reset_at}` : 'reset_at unknown'
      notes.push(`${vName}: skipped (breaker open${reasonPart}; ${resetPart})`)
      continue
    }

    if (vInfo.status !== 'ok') continue

    if (requiredTools.length > 0 && vInfo.toolSet !== null) {
      const missing = requiredTools.filter((t) => !vInfo.toolSet.has(t))
      if (missing.length > 0) {
        gatedVendors.add(vName)
        notes.push(`${vName}: skipped (harness lacks needed tool(s): ${missing.join(', ')})`)
        continue
      }
    }

    if (contextTokens !== null) {
      if (vInfo.ids.length === 0) {
        if (vInfo.topContextWindow !== null && vInfo.topContextWindow < contextTokens) {
          gatedVendors.add(vName)
          notes.push(`${vName}: skipped (context_window ${vInfo.topContextWindow} below required ${contextTokens})`)
        }
        continue
      }

      const keptIds = []
      let skippedAny = false
      for (const id of vInfo.ids) {
        const lower = id.toLowerCase()
        const cw = vInfo.contextWindowByModel.get(lower) ?? vInfo.topContextWindow ?? null
        if (cw !== null && cw < contextTokens) {
          vInfo.skippedModels.add(lower)
          skippedAny = true
          notes.push(`${vName} ${id}: skipped (context_window ${cw} below required ${contextTokens})`)
        } else {
          keptIds.push(id)
        }
      }
      if (skippedAny) {
        vInfo.ids = keptIds
        vInfo.idSet = new Set(keptIds.map((s) => s.toLowerCase()))
        vInfo.idCanonical = new Map(keptIds.map((s) => [s.toLowerCase(), s]))
        if (vInfo.defaultModel && vInfo.skippedModels.has(vInfo.defaultModel.toLowerCase())) {
          vInfo.defaultModel = keptIds[0] || null
        }
        if (keptIds.length === 0) {
          gatedVendors.add(vName)
        }
      }
    }
  }

  return { gatedVendors, claudeGated: gatedVendors.has('claude') }
}
