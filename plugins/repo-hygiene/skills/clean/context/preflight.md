# clean pre-flight runtime-safety check

Full detail for the §1.5 pre-flight gate (caches / build / all tiers). SKILL.md keeps the session-mode decision (the safety gate that aborts autonomous deletion); this file carries risk-class semantics, report format, and MCP-server side observations.

## Risk classes

Detect runtime conditions where deletion would corrupt active state:

1. **Active language runtimes** — `dotnet watch`, `aspire run`, attached debugger holding `bin/obj` file locks (Windows: Defender races + `MSB3027`)
2. **Running MCP servers** — `node` processes serving a bundled MCP server's build output over stdio; deletion mid-session crashes the server and breaks the parent Claude Code session
3. **Recent build activity** — `obj/project.assets.json` modified within last 10 minutes signals in-flight build / IDE indexing pass
4. **Open IDE** — Visual Studio / Rider holds analyzer DLL locks; partial deletion corrupts IDE state

## Detection (script)

Run the preflight script — do not reimplement detection inline:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/preflight.sh
```

**Output contract:**

- `RUNTIME_PROCS:` — process lines or empty
- `RECENT_BUILD:` — `project.assets.json` paths touched in last 10 minutes or empty
- `IDE_OPEN:` — IDE process lines or empty

**Consumer verdict** (SKILL §1.5): if any label is non-empty, present risks and [confirm](../SKILL.md#confirmation-gate) (or abort autonomous deletion per session mode). Script exit is always 0.

## Report format when risks fire

```
## Pre-flight: runtime risks detected

**Active runtimes:**
<RUNTIME_PROCS output, truncated to first 5 lines>

**Recent build activity (last 10 min):**
<RECENT_BUILD paths>

**Open IDE processes:**
<IDE_OPEN output>

**Risk:** deleting bin/obj/build dirs now may:
- crash live MCP servers (lose CC session connections)
- trigger MSB3027 file-lock errors mid-build
- corrupt IDE indexing / analyzer state (Visual Studio / Rider)

**Recommended:** close the IDE + stop dev servers, OR run the `scan` action to inventory only.
```

## Side observations on running MCP servers

When `RUNTIME_PROCS` contains a `node` process whose cmdline references a running MCP server, surface a one-line side note naming the specific MCP server. This skill should not auto-restart MCP servers; the user controls server lifecycle.
