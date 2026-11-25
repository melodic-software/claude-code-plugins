# GENERATED from lib/pr-verify-run.jq by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
.status == "completed" and .conclusion == "success"
  and .path == ".github/workflows/pr-verify.yml" and .event == "workflow_run" and .head_branch == $def
  and .repository.full_name == $repo and .head_repository.full_name == $repo
