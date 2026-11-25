# shellcheck shell=bash
# The sourcing drivers read these bodies, so SC2034 "appears unused" is a false positive here.
# shellcheck disable=SC2034

CCPERM_INTERP_BODY='python[0-9.]*|node|deno|bun|ruby|perl|php|bash|sh|zsh|pwsh|osascript|Rscript'
CCPERM_RUNNER_BODY='npx|bunx|uvx|pnpm dlx|yarn dlx|pipx run|uv run|npm|pnpm|yarn'
CCPERM_SCRIPT_BODY='py|sh|rb|js|ts|mjs|cjs|pl|php'
CCPERM_WRAPPER_BODY='timeout|time|nice|nohup|stdbuf|command|builtin|noglob'

CCPERM_BALANCED_ERE='([^()]|\([^()]*\))*'
CCPERM_P1_BLANKET_ERE="(Bash|PowerShell)\\(\\*\\)"
CCPERM_P1_INTERP_ERE="(Bash|PowerShell)\\([\"' ]*([^()\"' ]*[/\\\\])?(${CCPERM_INTERP_BODY})([\"' :]${CCPERM_BALANCED_ERE})?\\*${CCPERM_BALANCED_ERE}\\)"
CCPERM_P1_RUNNER_ERE="(Bash|PowerShell)\\([\"' ]*([^()\"' ]*[/\\\\])?(${CCPERM_RUNNER_BODY})(@[^()\"' :]*)?([\"' :]${CCPERM_BALANCED_ERE})?([\"' :])\\*${CCPERM_BALANCED_ERE}\\)"
CCPERM_P1_SCRIPTGLOB_ERE="(Bash|PowerShell)\\([\"' ]*\\*${CCPERM_BALANCED_ERE}\\.(${CCPERM_SCRIPT_BODY})${CCPERM_BALANCED_ERE}\\)"
CCPERM_P1_WRAPPER_ERE="Bash\\([\"' ]*(${CCPERM_WRAPPER_BODY})[\"' :]+\\*[\"' ]*\\)"
CCPERM_P1_LEADING_ERE="(Bash|PowerShell)\\([\"' ]*\\*${CCPERM_BALANCED_ERE}\\)"
CCPERM_P1_PATH_ERE="(Bash|PowerShell)\\([\"' ]*(\\\$HOME([/\\\\\"' :]${CCPERM_BALANCED_ERE})?|([^()\"' .\\\\]|[^()\"' \\\\][^()\"' \\\\]+)\\\\${CCPERM_BALANCED_ERE})\\*${CCPERM_BALANCED_ERE}\\)"
CCPERM_P1_ERE="${CCPERM_P1_BLANKET_ERE}|${CCPERM_P1_INTERP_ERE}|${CCPERM_P1_RUNNER_ERE}|${CCPERM_P1_SCRIPTGLOB_ERE}|${CCPERM_P1_WRAPPER_ERE}|${CCPERM_P1_LEADING_ERE}|${CCPERM_P1_PATH_ERE}"

CCPERM_TOOL_TOKEN_ERE="[A-Za-z_][A-Za-z0-9_]*(\\(${CCPERM_BALANCED_ERE}\\))?"
