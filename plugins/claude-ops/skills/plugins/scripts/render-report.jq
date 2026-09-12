# render-report.jq: the fixed-section report SKILL.md's Report section fixes,
# as a pure function of sync-run.sh's digest.
#
#   jq -r -f render-report.jq <run_dir>/digest.json
#
# sync-run.sh runs this once per invocation, writes the result to
# <run_dir>/report.txt, and prints it after the digest under `--render`. The
# same command reproduces the report from a run directory at any later time.
#
# Every section, conditional row, annotation and `Action needed` bullet is
# derived from a digest field; nothing here is judgment, so the report cannot
# misstate a number, an id, or a scope the digest carries. In audit mode every
# line that would be a mutation carries the `would run:` prefix, and the
# `Would withhold` row appears beside `Would update` whether or not a downgrade
# was found. Errors in a block's `errors[]` render under that block's
# `Action needed`; the run's own `errors[]` render under the trailing one.
#
# The one report line this program does not carry is the reload guidance,
# which the caller appends after the render.

def secs: if . == null then "n/a" else "\(.)s" end;
# The first line of a journaled CLI output that is the CLI's own, not the
# `$ <command>` echo the journal opens with.
def first_line: (. // "") | split("\n") | map(select(startswith("$ ") | not)) | (.[0] // "");
def pair: "\(.old) → \(.new)" + (if .direction == "unknown" then " (direction unknown)" else "" end);
def scoped: "\(.id) (\(.scope))";
def ids: map(.id) | join(", ");
def auto_update_slot:
  if . == true then "on"
  elif . == false then "off; enable it so the catalog refreshes at session start"
  else "unreadable" end;
def key_count: (capture("keys=(?<k>[0-9]+)") // {k: "?"}) | .k;

# The slowest timed step of a block's timings object, or null.
def slowest_step:
  [to_entries[] | select(.key != "total" and .key != "resolution" and .value != null)]
  | if length == 0 then null else max_by(.value) end;

def block($d):
  ($d.mode == "audit") as $audit
  | (.in_repo.updated + .user_sweep.updated) as $updated
  | (.in_repo.would_update + (.user_sweep.would_update | map(. + {scope: "user"}))) as $would
  | (.in_repo.failed + (.user_sweep.failed | map(. + {scope: "user"}))) as $failed
  | .user_sweep.withheld_downgrades as $withheld
  | ([.installed[] | select(.rc == 0)]) as $installed_ok
  | ([.installed[] | select(.rc != 0)]) as $installed_failed
  | ([.enabled[] | select(.predicted == true)]) as $would_enable
  | ([.enabled[] | select(.predicted != true and .rc == 0)]) as $enabled_ok
  | ([.enabled[] | select(.predicted != true and .rc != 0)]) as $enabled_failed
  | (.normalize.output // "") as $norm
  | (.normalize.project_report.output // "") as $pnorm
  | (.enable_gap - ($enabled_ok | map(.id)) - ($would_enable | map(.id))
     - (.project_enable_rows | map(.id))) as $enable_unfilled
  | (if $audit then
       (($would | length) > 0 or ($withheld | length) > 0
        or (.install_gap | length) > 0 or (.enable_gap | length) > 0)
     else
       (($failed | length) > 0 or ($withheld | length) > 0
        or .install_enable_deferred == true or .stopped_before_install == true
        or ($installed_failed | length) > 0 or ($enabled_failed | length) > 0
        or (.errors | length) > 0 or ($enable_unfilled | length) > 0
        or ((.install_gap | length) > 0 and ($installed_ok | length) == 0))
     end) as $needs
  | .timings as $t
  | [
      "Marketplace: \(.name): \(if $needs then "needs update" else "current" end) (autoUpdate: \(.auto_update | auto_update_slot))",
      (if $audit then
         "  would run: claude plugin marketplace update \(.name) (audit: predicted against the unrefreshed catalog, lastUpdated \(.catalog_last_updated // "unknown"); a lower bound on what sync would update)"
       elif .refresh.rc != null and .refresh.rc != 0 then
         "  refresh failed (exit \(.refresh.rc)): \(.refresh.output | first_line)"
       else empty end),

      # In-repo: a fixed row with three variants, picked by two digest fields.
      (if .project_root == null then
         "In-repo: skipped: no project context resolved from \($d.cwd // "the current directory")"
       elif .in_repo_records == null then
         "In-repo: unknown: no fleet-state snapshot was read for this marketplace"
       elif .in_repo_records == 0 then
         "In-repo: 0: \(.project_root) has no project/local installs"
       elif $audit then
         "In-repo: \(.in_repo.would_update | length) project/local install(s) would be updated in \(.project_root)"
       else
         "In-repo: \(.in_repo.updated | length) project/local install(s) updated in \(.project_root)"
       end),

      (if $audit then
         "Would update: \($would | length) plugin(s)",
         ($would[] | "  would run: claude plugin update \(.id) -s \(.scope) (installed \(.installed))"),
         ("Would withhold: \($withheld | length) downgrade(s)"
          + (if $d.allow_downgrade then " (--allow-downgrade ignored: audit issues no update either way)" else "" end)),
         ($withheld[] | "  - \(scoped): \(.installed) → \(.catalog) (catalog moved backward)")
       else
         (if ($updated | length) > 0 then
            "Updated: \($updated | length) plugin(s)",
            ($updated[] | "  - \(scoped): \(pair)")
          else empty end)
       end),

      (if (.downgraded | length) > 0 then
         "Downgraded: \(.downgraded | length) plugin(s)",
         (.downgraded[] | "  - \(scoped): \(.old) → \(.new)")
       else empty end),

      (if .catalog_regression != null then
         "Catalog regression: \(.catalog_regression.interval), "
         + (.catalog_regression.rows | map(split(" ") | "\(.[0]): \(.[1]) → \(.[2])") | join("; "))
       else empty end),

      (if $audit then
         (if $d.install_new == "all" and (.install_gap | length) > 0 and .install_enable_deferred != true then
            "Would install: \(.install_gap | length) new catalog plugin(s) (policy install_new: all, meaning these reinstall on every sync unless you also disable them)",
            (.install_gap[] | "  would run: claude plugin install \(.) -s user")
          else empty end)
       elif ($installed_ok | length) > 0 then
         "Installed: \($installed_ok | length) new catalog plugin(s): \($installed_ok | ids)"
         + (if $d.install_new == "all" then " (policy install_new: all, meaning these reinstall on every sync unless you also disable them)" else "" end)
       else empty end),

      (if ($norm | test("^normalized keys=")) then
         "Normalized: user enabledPlugins key order (\($norm | key_count) keys reordered)"
       elif ($norm | test("^would-normalize")) then
         "Would normalize: user enabledPlugins key order (would run: normalize-enabled-plugins.sh, \($norm | key_count) keys)"
       else empty end),

      (if ($would_enable | length) > 0 then
         "Would enable: \($would_enable | length) plugin(s)",
         ($would_enable[] | "  would run: claude plugin enable \(.id) -s \(.scope)")
       elif ($enabled_ok | length) > 0 then
         "Enabled: \($enabled_ok | length) plugin(s): \($enabled_ok | map(scoped) | join(", "))"
       else empty end),

      # Divergences: actionable only (versionsMatch false), split by interval.
      (.divergences as $v
       | if $v.post == null then
           "Divergences: not computed (\($v.note // "a snapshot was missing"))"
         else
           ("(\($v.new_total) newly created by this run: \($v.new_by_interval.in_repo) by the in-repo update, \($v.new_by_interval.user_sweep) by the user-scope sweep, \($v.pre_existing) pre-existing)") as $split
           | if $v.post == 0 then "Divergences: 0 actionable"
             elif .project_root != null and .divergences_here != null then
               "Divergences: \(.divergences_here) behind here → run `/claude-ops:plugins converge`; \($v.post - .divergences_here) more elsewhere on this machine \($split)"
             else
               "Divergences: \($v.post) actionable \($split) → run `/claude-ops:plugins converge`"
             end
         end),

      (if .self_updated == true then
         (($updated + .downgraded) | map(select(.id | test("^[^@]+@") )) | .[0]) as $row
         | "Note: this run updated \(($row.id // "this plugin") | split("@")[0]) (\($row.old // "?") → \($row.new // "?")). The algorithm that ran is the pre-update one:",
           "  ${CLAUDE_PLUGIN_ROOT} still resolves to the version loaded at session start. /reload-plugins",
           "  before relying on the new version."
       else empty end),

      (if (.stale_project_records.total // 0) > 0 then
         "Stale project records: \(.stale_project_records.total) record(s) across \(.stale_project_records.by_path | length) path(s) not present on this machine",
         (.stale_project_records.by_path[] | "  - \(.path): \(.count) record(s)"),
         "  (not counted as divergences: converge cannot cd into a path that is not present. A path can also",
         "   be absent because a volume is unmounted or a share is offline, so this is an observation, not a",
         "   verdict that the directory is gone for good.)"
       else empty end),

      (.cache_content as $c
       | if $c == null then empty
         elif ($c.stale_content // 0) > 0 then
           "Cache content: \($c.stale_content) install(s) whose cache files disagree with their recorded gitCommitSha",
           ($c.stale[] | if .files_differ == null then "  - \(.id)" else "  - \(.id) \(.version): \(.files_differ) file(s) differ" end),
           (if ($c.unverifiable // 0) > 0 then "  (checked \($c.checked): \($c.match) match, \($c.unverifiable) unverifiable; unverifiable is not a pass)" else empty end),
           "  Remediation: remove that version's directory under the plugin cache, then re-run",
           "  `claude plugin update <id>@<marketplace>`, which recreates it from the clone."
         elif ($c.unverifiable // 0) > 0 then
           "Cache content: \($c.unverifiable) of \($c.checked) install(s) unverifiable (recorded commit not in the local marketplace clone); no disagreement found among the rest"
         else empty end),

      (if $t == null then "Timing: n/a"
       else
         ($t | slowest_step) as $slow
         | "Timing: \($t.total | secs) this marketplace"
           + (if $slow == null then "" else "; slowest step \($slow.key) \($slow.value)s" end)
           + " (\($t.resolution))"
       end),

      # Action needed: omitted entirely when nothing needs action.
      ([
         (if .stopped_before_install == true then
            "\(.install_gap | length) catalog plugin(s) not installed at user scope (policy ask; stopped before Step 4 pending the batched prompt): \(.install_gap | join(", "))"
          elif .install_enable_deferred == true and (.install_gap | length) > 0 then
            "install gap deferred (marketplace refresh failed): \(.install_gap | join(", "))"
          elif ($d.install_new == "none" or ($audit and $d.install_new == "ask")) and (.install_gap | length) > 0 then
            "\(.install_gap | length) catalog plugin(s) not installed at user scope (policy \($d.install_new)): \(.install_gap | join(", "))"
          else empty end),
         (if .install_enable_deferred == true and (.enable_gap | length) > 0 then
            "enable gap deferred (marketplace refresh failed): \(.enable_gap | join(", "))"
          elif ($enable_unfilled | length) > 0 then
            "missing_from_enabled, not enabled this run: \($enable_unfilled | join(", "))"
          else empty end),
         (.project_enable_rows[]
          | "project-scope enable gap: (cd \"\(.project_path)\" && claude plugin enable \(.id) -s project)\n    Writes that repo's committed .claude/settings.json; review the diff before committing"),
         ($failed[] | "update failed (exit \(.rc)): \(.id) -s \(.scope): \(.output | first_line)"),
         ($installed_failed[] | "install failed (exit \(.rc)): \(.id): \(.output | first_line)"),
         ($enabled_failed[] | "enable failed (exit \(.rc)): \(.id) -s \(.scope): \(.output | first_line)"),
         (if (.user_scope_orphans | length) > 0 then
            "user-scope orphan(s), a project/local record with no user-scope install: \(.user_scope_orphans | join(", "))"
          else empty end),
         (.installed_with_unset_user_config[]
          | "\(.id): \(.options_unset) userConfig option(s) not yet set"
            + (if .required != null then " (\(.required) required)" else "" end)
            + "; run /plugin configure \(.id) in Claude Code, or pass --config KEY=VALUE"),
         (if (.updated_with_monitors | length) > 0 then
            "monitor(s) declared by updated plugin(s): \(.updated_with_monitors | map("\(.id) (\(.monitors))") | join(", ")); monitors require a session restart per plugins-reference, /reload-plugins does not cover them"
          else empty end),
         (if ($norm | test("^refused:")) then
            "user-scope enabledPlugins reorder refused: \($norm | first_line)"
          else empty end),
         (if ($pnorm | test("^project-unsorted")) then
            "project-scope enabledPlugins map is unsorted (\(.project_root // "?")/.claude/settings.json): converge is the only action that may rewrite it"
          else empty end),
         (if ($audit | not) and ($withheld | length) > 0 then
            "downgrade withheld: \($withheld | length) plugin(s), \($withheld | map("\(scoped): \(.installed) → \(.catalog)") | join(", ")); likely cause: marketplace source moved backward (\(.catalog_source // "source unknown")); rerun with --allow-downgrade only if the rollback is intended"
          else empty end),
         (.errors[] | "error: \(.)")
       ] | if length == 0 then empty else "Action needed:", (.[] | "  - \(.)") end)
    ]
  | join("\n");

. as $d
| [
    (if $d.mode == "audit" then "Audit (read-only): every mutating call below is a prediction, prefixed would run:" else empty end),
    ($d.marketplaces[] | block($d)),
    (if ($d.marketplaces | length) == 0 then "Marketplace: none resolved for this run" else empty end),
    "",
    (if $d.mode == "audit" then "Run: audit scratch directory, removed on exit"
     else "Run journal: \($d.run_dir)" end),
    "Timing: \($d.timings.total | secs) whole invocation (\($d.timings.resolution))",
    ([
       (if $d.install_new_invalid != null then
          "install_new value \"\($d.install_new_invalid)\" is not all, none, or ask; this run used ask"
        else empty end),
       ($d.errors[] | "error: \(.)")
     ] | if length == 0 then empty else "Action needed:", (.[] | "  - \(.)") end)
  ]
| join("\n")
