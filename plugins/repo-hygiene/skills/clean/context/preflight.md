# clean pre-flight runtime-safety check

Full detail for the §1.5 pre-flight gate (caches / build / all tiers). SKILL.md keeps the session-mode decision (the safety gate that aborts autonomous deletion); this file carries risk-class semantics, report format, and MCP-server side observations.

## Risk classes

Detect runtime conditions where deletion would corrupt active state:

1. **Active language runtimes**: `dotnet watch`, `aspire run`, attached debugger holding `bin/obj` file locks (Windows: Defender races + `MSB3027`)
2. **Running MCP servers**: `node` processes serving a bundled MCP server's build output over stdio; deletion mid-session crashes the server and breaks the parent Claude Code session
3. **Recent build activity**: `obj/project.assets.json` modified within last 10 minutes signals in-flight build / IDE indexing pass
4. **Open IDE**: Visual Studio / Rider holds analyzer DLL locks; partial deletion corrupts IDE state

## Detection (script)

Run the preflight script. Do not reimplement detection inline:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/preflight.sh [ROOT...]
```

Pass the repositories about to be cleaned as ROOTs. With no ROOT the scope is the invoking repository.

**Output contract:**

- `RUNTIME_PROCS:` runtime process lines scoped to the ROOTs, or empty. A process is in scope when its working directory or command line is at or under a ROOT. Each line ends `[repo: <ROOT>]` (the longest matching ROOT), and at most 5 print. On Windows (no `/proc`) the list is machine-wide and marked `(unscoped)`.
- `RECENT_BUILD:` `project.assets.json` paths touched in last 10 minutes under the ROOTs, or empty
- `IDE_OPEN:` IDE process lines, or empty. Always machine-wide (`tasklist`, Windows only), marked `(unscoped)` when non-empty.
- `RUNTIME_PROCS_UNATTRIBUTED:` count of runtime-process matches elsewhere on the machine, or `n/a (unscoped)` on Windows. These are not risks to the scanned repositories and do not trigger the verdict; a process whose working directory cannot be read counts here.

**Consumer verdict** (SKILL §1.5): if `RUNTIME_PROCS`, `RECENT_BUILD`, or `IDE_OPEN` is non-empty, present risks and [confirm](../SKILL.md#confirmation-gate) (or abort autonomous deletion per session mode). Script exit is always 0.

## Report format when risks fire

```
## Pre-flight: runtime risks detected

**Active runtimes:**
<RUNTIME_PROCS lines (at most 5 print), each tagged repo:>

**Recent build activity (last 10 min):**
<RECENT_BUILD paths>

**Open IDE processes:**
<IDE_OPEN output (machine-wide, unscoped)>

**Risk:** deleting bin/obj/build dirs now may:
- crash live MCP servers (lose CC session connections)
- trigger MSB3027 file-lock errors mid-build
- corrupt IDE indexing / analyzer state (Visual Studio / Rider)

**Recommended:** close the IDE + stop dev servers, OR run the `scan` action to inventory only.
```

## Side observations on running MCP servers

When `RUNTIME_PROCS` contains a `node` process whose cmdline references a running MCP server, surface a one-line side note naming the specific MCP server. This skill should not auto-restart MCP servers; the user controls server lifecycle.
