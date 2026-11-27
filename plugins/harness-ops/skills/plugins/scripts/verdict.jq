# verdict.jq: the classify step of the sync and audit report. classify reads a
# sync-run.sh digest and returns its verdict facts as data, one object per
# marketplace block and one for the run; render-report.jq formats them, and
# sync-run.sh writes them into the digest as each block's and the run's
# `verdict` (keys in digest-contract.json).

# The first line of a journaled CLI output that is the CLI's own, not the
# `$ <command>` echo the journal opens with.
def first_line: (. // "") | split("\n") | map(select(startswith("$ ") | not)) | (.[0] // "");
# Capture-time classification lives in .reason. This fallback is the same rule
# as sync-run.sh's cli_outcome_line for a row that has no reason yet: CRs
# dropped, `$` and empty lines skipped, then the first ✘ / Failed / Error line,
# else the first line left. Not the last line, which can be a userConfig note.
def outcome_line:
  (. // "") | gsub("\r"; "") | split("\n")
  | map(select((startswith("$ ") | not) and . != "")) as $lines
  | ([$lines[] | select(startswith("✘") or contains("Failed") or contains("Error"))][0])
    // $lines[0] // "";
def reported:
  if (.reason | type) == "string" and .reason != "" then .reason
  else (.output | outcome_line) end;
def scoped: "\(.id) (\(.scope))";
# A labeled list as lines: inline up to three entries, past that one `- `
# entry per line under the label. The caller indents the entry lines.
def listed($head; $items):
  if ($items | length) <= 3 then ["\($head): \($items | join(", "))"]
  else ["\($head):"] + ($items | map("- \(.)")) end;
# A digest written before sync-run.sh parsed the normalizer line carries only
# `output`, read here into the same fields.
def norm_fields:
  if . == null then {}
  elif has("status") then .
  else (.output // "") as $o
    | {status: ($o | if test("^normalized ") then "normalized" elif test("^would-normalize") then "would-normalize"
                 elif test("^missing-file") then "missing-file" elif test("^refused:") then "refused"
                 elif test("^project-unsorted") then "project-unsorted" else null end),
       moved: ($o | capture("moved=(?<m>[0-9]+)").m // null),
       keys: ($o | capture("keys=(?<k>[0-9]+)").k // null),
       reason: ($o | first_line | ltrimstr("refused: "))}
  end;
def item($kind): {kind: $kind, lines: .};

# One marketplace block's facts: its status, the pending actions and their
# kinds, whether the run changed (in audit, would change) anything, the install
# and enable outcomes, and every `Action needed` item as {kind, lines}.
def classify_block($d):
  ($d.mode == "audit") as $audit
  | (.in_repo.updated + .user_sweep.updated) as $updated
  | (.in_repo.would_update + (.user_sweep.would_update | map(. + {scope: "user"}))) as $would
  | (.in_repo.failed + (.user_sweep.failed | map(. + {scope: "user"}))) as $failed
  | .user_sweep.withheld_downgrades as $withheld
  | .other_paths as $op
  | ([.installed[] | select(.predicted == true)]) as $would_install
  | ([.installed[] | select(.predicted != true and .rc == 0)]) as $installed_ok
  | ([.installed[] | select(.predicted != true and .rc != 0)]) as $installed_failed
  | (.install_gap - ($installed_ok | map(.id))) as $install_left
  | ([.enabled[] | select(.predicted == true)]) as $would_enable
  | ([.enabled[] | select(.predicted != true and .rc == 0)]) as $enabled_ok
  | ([.enabled[] | select(.predicted != true and .rc != 0)]) as $enabled_failed
  # An install the CLI left disabled by default that this run did not then
  # enable at user scope.
  | ([$enabled_ok[] | select(.scope == "user") | .id]) as $on
  | [$installed_ok[] | select(.disabled_by_default == true) | .id | select(IN($on[]) | not)] as $installed_disabled
  | (.normalize | norm_fields) as $norm
  | (.normalize.project_report | norm_fields) as $pnorm
  | (.enable_gap - ($enabled_ok | map(.id)) - ($would_enable | map(.id))
     - (.project_enable_rows | map(.id))) as $enable_unfilled
  | (.install_enable_deferred == true and (.install_gap | length) > 0
     and .stopped_before_install != true) as $install_deferred
  | (.install_enable_deferred == true and (.enable_gap | length) > 0) as $enable_deferred
  # The `Action needed` items for pending actions: work this run left to a person
  # (an install declined, skipped by policy or held for the ask prompt, an unfilled
  # enable, a withheld downgrade, a delisted plugin). The header counts them; a gap
  # deferred by a failed refresh is refresh state instead, so it is not among them.
  | (.install_held == "all-target") as $held
  | [if .stopped_before_install == true and $held then
       listed("\(.install_gap | length) catalog plugin(s) not installed at user scope (install held: policy all across every marketplace would install every catalog, so a person picks)"; .install_gap)
       + (if $audit then ["sync would stop before Step 4 and offer them through the ask prompt"]
          else ["remedy: pick from the ask offer, then rerun with --only-install <picked ids> --run-dir <run journal>"] end)
     elif .stopped_before_install == true then
       listed("\(.install_gap | length) catalog plugin(s) not installed at user scope (policy ask, stopped before Step 4 pending the batched prompt)"; .install_gap)
     elif $install_deferred then empty
     elif ($audit | not) and ($d.install_new == "ask" or $held) and ($install_left | length) > 0 then
       listed("\($install_left | length) catalog plugin(s) offered and not installed (\(if $held then "install held for the all-marketplaces target" else "policy ask" end))"; $install_left)
       + ["remedy: disable any you never want with enabledPlugins: false, or ask offers it again on every sync"]
     elif ($d.install_new == "none" or ($audit and $d.install_new == "ask")) and (.install_gap | length) > 0 then
       listed("\(.install_gap | length) catalog plugin(s) not installed at user scope (policy \($d.install_new))"; .install_gap)
     else empty end | item("install")] as $install_pending
  | [(if ($enable_deferred | not) and ($enable_unfilled | length) > 0 then
        listed("missing_from_enabled, not enabled this run"; $enable_unfilled)
      else empty end | item("enable")),
     (.project_enable_rows[]
      | ["project-scope enable gap: \(.id) in \(.project_path)",
         "remedy: (cd \"\(.project_path)\" && claude plugin enable \(.id) -s project)",
         "that writes the repo's committed .claude/settings.json, so review the diff before committing"]
      | item("project_enable"))] as $enable_pending
  | [$installed_disabled[]
     | ["\(.): installed but not enabled", "remedy: claude plugin enable \(.) -s user"] | item("disabled")] as $disabled_pending
  | [(if (.delisted | length) == 0 then empty
      elif $audit then
        listed("delisted, absent from the unrefreshed catalog (audit prediction)"; .delisted)
        + ["sync names any still absent after its refresh, with the remedy"]
      else
        listed("delisted, absent from the catalog"; .delisted)
        + ["remedy: uninstall each with `claude plugin uninstall <id> -s user`"]
      end),
     (if (.delisted_project | length) == 0 then empty
      elif $audit then
        listed("delisted in this repo, absent from the unrefreshed catalog (audit prediction)"; .delisted_project | map(scoped))
        + ["sync names any still absent after its refresh, with the remedy"]
      else
        (.project_root // "?") as $root
        | (.delisted_project[]
           | ["delisted in this repo, absent from the catalog: \(scoped)",
              "remedy: (cd \"\($root)\" && claude plugin uninstall \(.id) -s \(.scope))"])
      end),
     (if (.delisted_settings_only | length) == 0 then empty
      elif $audit then
        listed("enabled in settings, not installed, and absent from the unrefreshed catalog (audit prediction)"; .delisted_settings_only)
        + ["sync names any still absent after its refresh, with the remedy"]
      else
        listed("enabled in settings, not installed, and absent from the catalog"; .delisted_settings_only)
        + ["remedy: remove each key from enabledPlugins in the settings file that sets it"]
      end) | item("delisted")] as $delisted_pending
  | [if ($audit | not) and ($withheld | length) > 0 then
       ["downgrade withheld: \($withheld | length) plugin(s)"]
       + ($withheld | map("- \(scoped): \(.installed) -> \(.catalog)"))
       + ["likely cause: marketplace source moved backward (\(.catalog_source // "source unknown"))",
          "remedy: rerun with --allow-downgrade only if the rollback is intended"]
     else empty end | item("withheld")] as $withheld_pending
  # Audit predicts a withheld downgrade as its `Would withhold` row, not a bullet;
  # it counts as one pending action.
  | ($install_pending + $enable_pending + $disabled_pending + $delisted_pending + $withheld_pending
     + (if $audit and ($withheld | length) > 0 then [[] | item("withheld")] else [] end)) as $pending
  # `needs update`: refresh, update and failure state only. Audit predicts what sync
  # would update, install or enable itself.
  | (if $audit then
       (($would | length) > 0 or ($would_enable | length) > 0 or ($op.would_update | length) > 0
        or ($would_install | length) > 0)
     else
       (($failed | length) > 0 or .install_enable_deferred == true or ($op.failed | length) > 0
        or ($installed_failed | length) > 0 or ($enabled_failed | length) > 0
        or (.errors | length) > 0)
     end) as $needs
  | .source_checkout as $src
  | .source_pull as $pull
  | (($src.behind // 0) > 0) as $behind
  # What the verdict calls a change: something this run moved, or in audit
  # something sync would move or withhold.
  | (if $audit then ($needs or $norm.status == "would-normalize" or ($withheld | length) > 0)
     else
       (($updated | length) > 0 or (.downgraded | length) > 0 or ($installed_ok | length) > 0
        or ($op.updated | length) > 0
        or ($enabled_ok | length) > 0 or $norm.status == "normalized" or $pull.status == "pulled")
     end) as $changed
  | [
      (if $behind then
         ["source checkout \($src.path) is \($src.behind) commit(s) behind \($src.upstream), and the catalog is read from it as it is",
          "remedy: run `git -C \($src.path | @sh) pull --ff-only`, then rerun `/harness-ops:plugins sync \(.name)`"]
         + (if $src.ahead > 0 then ["it also carries \($src.ahead) local commit(s), so --ff-only refuses until they are reconciled"] else [] end)
         + (if $src.dirty then ["tracked files are modified, and the pull refuses if it would overwrite them"] else [] end)
         | item("source_behind")
       else empty end),
      # A requested fast-forward that did not happen. HEAD and the work tree are
      # as they were, so the behind item above, when there is one, still stands.
      (if $pull.status == "refused" then
         ["requested fast-forward of \($src.path // "the source checkout") refused, nothing changed: \($pull.reason)"]
         | item("pull_refused")
       elif $pull.status == "failed" then
         ["requested fast-forward of \($src.path // "the source checkout") failed (exit \($pull.rc)): \($pull.reason)"]
         | item("pull_failed")
       else empty end),
      (if $install_deferred then
         listed("install gap deferred (marketplace refresh failed)"; .install_gap) | item("install_deferred")
       else empty end),
      $install_pending[],
      (if $enable_deferred then
         listed("enable gap deferred (marketplace refresh failed)"; .enable_gap) | item("enable_deferred")
       else empty end),
      $enable_pending[],
      ($failed[] | if .stopped == true then ["update stopped in \(.path): \(.id) -s \(.scope): \(.reason)"] | item("update_stopped")
                   else ["update failed (exit \(.rc)): \(.id) -s \(.scope): \(reported)"] | item("update_failed") end),
      ($op.failed[]
       | ["update \(if .stopped then "stopped" else "failed" end) in \(.path): \(.id) -s \(.scope): \(.reason)"]
       | item("other_path_failed")),
      ($installed_failed[] | ["install failed (exit \(.rc)): \(.id): \(reported)"] | item("install_failed")),
      ($enabled_failed[] | ["enable failed (exit \(.rc)): \(.id) -s \(.scope): \(reported)"] | item("enable_failed")),
      $disabled_pending[],
      $delisted_pending[],
      (if (.user_scope_orphans | length) > 0 then
         listed("user-scope orphan(s), a project/local record with no user-scope install"; .user_scope_orphans)
         | item("user_scope_orphans")
       else empty end),
      (.installed_with_unset_user_config[]
       | ["\(.id): \(.options_unset) userConfig option(s) not yet set"
          + (if .required != null then " (\(.required) required)" else "" end),
          "remedy: run /plugin configure \(.id) in Claude Code, or pass --config KEY=VALUE"]
       | item("unset_user_config")),
      (if (.updated_with_monitors | length) > 0 then
         listed("monitor(s) declared by updated plugin(s)"; .updated_with_monitors | map("\(.id) (\(.monitors))"))
         + ["remedy: restart the session to run the updated monitors, /reload-plugins does not switch them"]
         | item("monitors")
       else empty end),
      (if $norm.status == "refused" then
         ["user-scope enabledPlugins reorder refused: \($norm.reason)"] | item("normalize_refused")
       else empty end),
      (if $pnorm.status == "project-unsorted" then
         ["project-scope enabledPlugins map is unsorted (\(.project_root // "?")/.claude/settings.json)",
          "remedy: run converge, the only action that may rewrite it"]
         | item("project_unsorted")
       else empty end),
      $withheld_pending[],
      (.errors[] | ["error: \(.)"] | item("error"))
    ] as $actions
  | {status: (if $needs then "needs_update" elif $behind then "source_behind" else "current" end),
     needs_update: $needs,
     changed: $changed,
     pending: ($pending | length),
     pending_kinds: [$pending[].kind],
     actions: $actions,
     installed: {ok: [$installed_ok[].id], failed: [$installed_failed[].id],
                 predicted: [$would_install[] | {id, label}], left: $install_left},
     enabled: {ok: [$enabled_ok[] | {id, scope}], failed: [$enabled_failed[] | {id, scope}],
               predicted: [$would_enable[] | {id, scope, label}], unfilled: $enable_unfilled},
     installed_disabled: $installed_disabled};

# The run's facts and each block's: the run's own `Action needed` items, the
# count of every item, and the result the report opens with.
def classify:
  . as $d
  | ($d.mode == "audit") as $audit
  | [$d.marketplaces[] | classify_block($d)] as $blocks
  | [(if $d.install_new_invalid != null then
        ["install_new value \"\($d.install_new_invalid)\" is not all, none, or ask", "this run used ask"]
        | item("install_new_invalid")
      else empty end),
     (if $d.source_pull_invalid != null then
        ["directory_source_pull value \"\($d.source_pull_invalid)\" is not ask or never", "this run used \($d.source_pull)"]
        | item("source_pull_invalid")
      else empty end),
     ($d.errors[] | ["error: \(.)"] | item("error"))] as $actions
  # The result counts every `Action needed` item, the blocks' and the run's. A
  # remedy on a row outside that section (converge, autoUpdate) is not one of them.
  | (([$blocks[].actions | length] | add // 0) + ($actions | length)) as $count
  | {blocks: $blocks,
     run: {result: (if $count > 0 then "action_needed"
                    elif $audit then (if any($blocks[]; .changed) then "predicted" else "no_change_predicted" end)
                    elif any($blocks[]; .changed) then "changed"
                    else "clean" end),
           action_count: $count,
           actions: $actions}};

# The digest with each block's and the run's `verdict` filled in.
def with_verdict:
  classify as $v
  | .verdict = $v.run
  | .marketplaces |= [to_entries[] | .value + {verdict: $v.blocks[.key]}];
