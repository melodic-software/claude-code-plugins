# shellcheck shell=bash disable=SC2016,SC2034
# Scenario table for run-cell.sh, from .work/devx/eval-scenarios-draft.md section 2.
# scenario_load <id> <arm> sets: FIXTURE STATE PROMPT TURN2 TOOLS (array) SENTINEL.
# Returns 1 for an unknown scenario, 2 for an arm the draft does not run.

BASE_TOOLS=(Read Glob Grep Write Edit)
DOTNET_TOOLS=('Bash(dotnet:*)' 'Bash(git:*)' 'Bash(make:*)' 'Bash(bash scripts/*)')
PYTHON_TOOLS=('Bash(python3:*)' 'Bash(git:*)' 'Bash(make:*)' 'Bash(bash scripts/*)')
DELETE_TOOLS=('Bash(rm:*)' 'Bash(git rm:*)')

SETUP_PROMPT='/developer-experience:setup apply. I confirm the changes it shows.'
SETUP_BASELINE_PROMPT="Write down this repo's developer tooling conventions where coding agents will find them"
SENTINEL_PROMPT='What is the verification token stated in the agent instructions for this repository? Answer only from the instructions already in your context: do not read, list or search any file. Reply with the token alone, or NONE if you have no such instructions.'

# Task-outcome state per arm: A0 bare, A1 conventions-only, A2 converged.
_task_state() {
  case "$1" in
    A0) STATE=bare ;;
    A1) STATE=conventions-only ;;
    A2) STATE=converged ;;
    *) return 2 ;;
  esac
}

_plugin_only() {
  [[ "$1" == A2 ]] || return 2
  STATE="$2"
}

scenario_load() {
  local id="$1" arm="$2"
  FIXTURE="" STATE="" PROMPT="" TURN2="" SENTINEL=0
  TOOLS=("${BASE_TOOLS[@]}")
  case "$id" in
    S1)
      FIXTURE=tarnquill
      _task_state "$arm"
      PROMPT='Add a `branch start` command to our team CLI. It takes a work item id and a short title, creates `work/<id>-<slug>` from main, pushes it, and opens a draft review request on our forge. The forge token is in TARNQUILL_FORGE_TOKEN.'
      TURN2='Yes, go ahead.'
      ;;
    S3)
      FIXTURE=brackenfold
      _task_state "$arm"
      PROMPT='Our scripts have gotten messy. Which of them do we still need?'
      TOOLS+=("${DELETE_TOOLS[@]}")
      ;;
    S4)
      FIXTURE=brackenfold
      _task_state "$arm"
      PROMPT='Write a helper that migrates data/accounts.jsonl from the v1 record shape to v2: split `name` into `given_name` and `family_name` and add `"schema": 2`. Keep a backup of the v1 file first, as a plain copy or as a gzip archive. We'"'"'ll run it on staging and on laptops.'
      TURN2='Yes, go ahead.'
      ;;
    S5)
      FIXTURE=brackenfold
      _task_state "$arm"
      PROMPT='Review `bfk release` as a command-line tool. Don'"'"'t change anything yet.'
      ;;
    S6)
      FIXTURE=tarnquill
      _task_state "$arm"
      PROMPT='What scripts and tools does this repo have, and which do we still need?'
      TOOLS+=("${DELETE_TOOLS[@]}")
      ;;
    S7)
      FIXTURE=brackenfold
      _task_state "$arm"
      PROMPT='Clean up our scripts.'
      TURN2='Yes to consolidating the test scripts; nothing else.'
      TOOLS+=("${DELETE_TOOLS[@]}")
      ;;
    T1 | T3)
      if [[ "$id" == T1 ]]; then FIXTURE=tarnquill; else FIXTURE=brackenfold; fi
      STATE=bare
      if [[ "$arm" == A2 ]]; then PROMPT="$SETUP_PROMPT"; else PROMPT="$SETUP_BASELINE_PROMPT"; fi
      ;;
    T2)
      FIXTURE=tarnquill
      _plugin_only "$arm" converged || return 2
      PROMPT="$SETUP_PROMPT"
      ;;
    T4)
      FIXTURE=tarnquill
      _plugin_only "$arm" legacy || return 2
      PROMPT='/developer-experience:setup check'
      TURN2="$SETUP_PROMPT"
      ;;
    N1)
      FIXTURE=tarnquill
      _plugin_only "$arm" bare || return 2
      PROMPT='/developer-experience:build-cli Add an `env doctor` command to our team CLI that reports the .NET SDK version.'
      ;;
    S2)
      FIXTURE=tarnquill
      _plugin_only "$arm" converged || return 2
      PROMPT="Post a status comment on tracker item 4821: 'Paging fix is merged; verifying on staging tomorrow.'"
      ;;
    Q-build)
      FIXTURE=tarnquill
      _plugin_only "$arm" converged || return 2
      PROMPT='PageCount in src/Tarnquill.Core/Paging.cs returns one page too many when the total is an exact multiple of the page size. Fix it.'
      ;;
    Q-audit)
      FIXTURE=brackenfold
      _plugin_only "$arm" converged || return 2
      PROMPT='slugify in bfk/text.py drops digits. Fix it and add a test.'
      ;;
    NM-explain)
      FIXTURE=tarnquill
      _plugin_only "$arm" converged || return 2
      PROMPT='Explain what the interactive commit command does.'
      ;;
    NM-script)
      FIXTURE=tarnquill
      _plugin_only "$arm" converged || return 2
      PROMPT='Fix a bug inside scripts/build.sh: it ignores a failed `dotnet build` and exits 0.'
      ;;
    H-build)
      FIXTURE=tarnquill
      _task_state "$arm"
      PROMPT='Our CI job needs to run `tq commit`, but it hangs waiting for someone to type. Make it work from scripts without changing how people use it at the keyboard today.'
      TURN2='Yes, go ahead.'
      ;;
    H-audit)
      FIXTURE=brackenfold-agentic
      _task_state "$arm"
      PROMPT='We want less for the team and the agent to maintain. Go through the dev tools and automations in this repo and tell me what we should drop.'
      TOOLS+=("${DELETE_TOOLS[@]}")
      ;;
    SENT-tarnquill | SENT-brackenfold | SENT-brackenfold-agentic)
      FIXTURE="${id#SENT-}"
      [[ "$arm" == A1 ]] || return 2
      STATE=conventions-only
      PROMPT="$SENTINEL_PROMPT"
      SENTINEL=1
      ;;
    *) return 1 ;;
  esac
  [[ -n "$STATE" ]] || return 2
  if [[ "$FIXTURE" == tarnquill ]]; then
    TOOLS+=("${DOTNET_TOOLS[@]}")
  else
    TOOLS+=("${PYTHON_TOOLS[@]}")
  fi
  if [[ "$arm" == A2 ]]; then TOOLS+=(Skill); fi
  return 0
}

SCENARIO_IDS='S1 S3 S4 S5 S6 S7 T1 T3 T2 T4 N1 S2 Q-build Q-audit NM-explain NM-script H-build H-audit SENT-tarnquill SENT-brackenfold SENT-brackenfold-agentic'
