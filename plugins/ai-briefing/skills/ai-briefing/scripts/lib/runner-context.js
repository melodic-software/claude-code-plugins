// Command context wrapper + centralized exit dispatch for per-profile-runner.

/** @typedef {{ code: number, payload?: object, saveProfile?: boolean, saveMaster?: boolean, appendLog?: object }} CommandResult */

export function exitWith(code, payload) {
  if (payload !== undefined) {
    process.stdout.write(`${JSON.stringify(payload)}\n`);
  }
  process.exit(code);
}

export function createWithProfile(deps) {
  const { getStateForRun, getOrInitProfile } = deps;

  async function withProfile(flags, handler, options = {}) {
    const { includeComplete = false, requireIndex = false, skipStateLoad = false } = options;

    /** @type {Record<string, unknown>} */
    const ctx = { flags };

    if (!skipStateLoad) {
      const loaded = await getStateForRun(flags, { includeComplete });
      Object.assign(ctx, loaded);
    }

    if (requireIndex) {
      const index = Number(flags.index);
      if (!Number.isInteger(index)) throw new Error("--index=<N> required");
      const profileCtx = await getOrInitProfile(ctx.state, ctx.master, index);
      Object.assign(ctx, { index, ...profileCtx });
    }

    const result = await handler(ctx);

    if (result.saveProfile && ctx.profile) {
      await ctx.state.saveProfile(ctx.profile);
    }
    if (result.saveMaster) {
      await ctx.state.saveMaster(ctx.master);
    }
    if (result.appendLog) {
      await ctx.state.appendLog(result.appendLog);
    }

    return result;
  }

  function profileCmd(options, handler) {
    return (flags) => withProfile(flags, handler, options);
  }

  return { withProfile, profileCmd };
}
