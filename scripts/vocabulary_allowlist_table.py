"""One row per shipped allowlist entry in vocabulary-senses.json, with a line it must keep."""

from __future__ import annotations

GUIDE = "docs/guide.md"
RUNG_LINE = "The rung opens the page."
OVERLAY_LINE = "The overlay layers on the shipped defaults."
TIER_LINE = "The tier overrides the default."
SURFACE_LINE = "The surface reads settings.json."
CONTRACT_LINE = "The contract locks the brief."
EVAL = "plugins/x/evals/case/samples/a.json"


def phrase(sense: str, regex: str, line: str):
    return (sense, "phrase", regex, GUIDE, line)


def path(sense: str, glob: str, file: str, line: str):
    return (sense, "path", glob, file, line)


JUDGE_CALIBRATION = "plugins/testing/skills/audit/evals/judge-calibration/**"


def eval_rows(sense: str, line: str):
    return [
        path(sense, "**/evals/**/samples/**", EVAL, line),
        path(
            sense, "**/evals/**/graders/**", "plugins/x/evals/case/graders/a.md", line
        ),
        (
            sense,
            "phrase",
            r"""^\s*(?:-\s*)?pattern:\s*['"]""",
            GUIDE,
            f"    pattern: '{line}'",
        ),
        path(
            sense, JUDGE_CALIBRATION, JUDGE_CALIBRATION.replace("**", "case.md"), line
        ),
    ]


ALLOWLIST = [
    phrase(
        "rung",
        r"\bautonomy (ladder|rungs?)\b",
        "The autonomy ladder rung for a page stays.",
    ),
    path("rung", "plugins/autonomy/**", "plugins/autonomy/README.md", RUNG_LINE),
    phrase(
        "rung",
        r"\benforcement[- ]ladder\b",
        "The enforcement ladder's rung for a page stays.",
    ),
    path(
        "rung",
        "docs/contracts/enforcement-ladder/**",
        "docs/contracts/enforcement-ladder/v1.md",
        RUNG_LINE,
    ),
    path(
        "rung",
        "docs/conventions/enforcement-ladder/**",
        "docs/conventions/enforcement-ladder/README.md",
        RUNG_LINE,
    ),
    path("rung", "**/enforcement-ladder.md", "docs/enforcement-ladder.md", RUNG_LINE),
    phrase(
        "rung",
        r"\bresolution ladder\b",
        "The resolution ladder's rung for a page stays.",
    ),
    path("rung", "plugins/toolchain/**", "plugins/toolchain/README.md", RUNG_LINE),
    phrase(
        "rung", r"\bmethod[- ]ladder\b", "The method ladder's rung for a page stays."
    ),
    path(
        "rung",
        "plugins/github/reference/method-ladder.md",
        "plugins/github/reference/method-ladder.md",
        RUNG_LINE,
    ),
    phrase(
        "rung",
        r"\b(loop[- ]lane|pr[- ]pipeline)\b.*\brungs?\b",
        "The loop-lane rung for a page stays.",
    ),
    path(
        "rung",
        "docs/contracts/loop-lane/**",
        "docs/contracts/loop-lane/v1.md",
        RUNG_LINE,
    ),
    path(
        "rung",
        "docs/conventions/loop-lane/**",
        "docs/conventions/loop-lane/README.md",
        RUNG_LINE,
    ),
    path(
        "rung",
        "docs/conventions/pr-pipeline/**",
        "docs/conventions/pr-pipeline/README.md",
        RUNG_LINE,
    ),
    path(
        "rung",
        "plugins/session-flow/skills/find-handoff/**",
        "plugins/session-flow/skills/find-handoff/SKILL.md",
        RUNG_LINE,
    ),
    phrase(
        "rung",
        r"\b(explanation rungs?|rungs? of explanation)\b",
        "The explanation rung sits above the page.",
    ),
    phrase(
        "rung", r"\bcandidate ladder\b", "The candidate ladder's rung for a page stays."
    ),
    path(
        "rung",
        "plugins/session-flow/skills/recommend-skills/**",
        "plugins/session-flow/skills/recommend-skills/SKILL.md",
        RUNG_LINE,
    ),
    *eval_rows("rung", RUNG_LINE),
    phrase(
        "rung", r"\bfetch-route rungs?\b", "Read the page by the fetch-route rungs."
    ),
    path(
        "rung",
        "docs/contracts/upstream-drift/**",
        "docs/contracts/upstream-drift/README.md",
        RUNG_LINE,
    ),
    *(
        path("rung", file, file, RUNG_LINE)
        for file in (
            "plugins/attribution/prerequisites.json",
            "plugins/attribution/skills/audit/reference/source-fetch.md",
            "plugins/instruction-placement/skills/migrate/reference/sources.md",
            "plugins/plugin-quality/README.md",
            "plugins/plugin-quality/agents/auditor.md",
            "plugins/plugin-quality/prerequisites.json",
            "plugins/knowledge/reference/ingest-deferred-decisions.md",
        )
    ),
    path(
        "rung",
        "plugins/knowledge/skills/map-corpus/**",
        "plugins/knowledge/skills/map-corpus/SKILL.md",
        RUNG_LINE,
    ),
    phrase(
        "rung",
        r"\brung [0-9]+ instruction\b",
        "The rung 5 instruction on the page says to type next.",
    ),
    phrase("rung", r"\brung-up\b", "The rung-up's page stops."),
    phrase("rung", r"\bASR[- ]rung\b", "The ASR rung needs the media file."),
    path(
        "rung",
        "plugins/knowledge/skills/video-digest/**",
        "plugins/knowledge/skills/video-digest/SKILL.md",
        RUNG_LINE,
    ),
    phrase(
        "rung",
        r"\bcode-rung\b|\bneighboring rungs\b",
        "Code-rung diagrams are out of scope.",
    ),
    path(
        "rung",
        "plugins/discovery/skills/research/**",
        "plugins/discovery/skills/research/SKILL.md",
        RUNG_LINE,
    ),
    phrase(
        "rung",
        r"\brung rather than a hope\b",
        "It makes resume the first rung rather than a hope; no page says more.",
    ),
    phrase(
        "rung",
        r"\bpartitioning the rungs\b",
        "The root coordinates at medium, partitioning the rungs.",
    ),
    path(
        "rung",
        "plugins/songwriting/skills/suno/**",
        "plugins/songwriting/skills/suno/SKILL.md",
        RUNG_LINE,
    ),
    path(
        "rung",
        "plugins/source-control/skills/babysit-*/**",
        "plugins/source-control/skills/babysit-loop/SKILL.md",
        RUNG_LINE,
    ),
    phrase(
        "rung",
        r"\bsame-machine rung\b",
        "Portability no longer bars a same-machine rung for the page.",
    ),
    phrase(
        "rung",
        r"\bsimplifier\b.*\brungs?\b",
        "The simplifier's third rung is a fallback for the page.",
    ),
    phrase(
        "rung",
        r"\bproject-convention-files rung\b",
        "Read it at the project-convention-files rung of the page.",
    ),
    phrase(
        "default-ladder",
        r"\bautonomy\b",
        "The autonomy default ladder starts at observe.",
    ),
    phrase(
        "default-ladder",
        r"\benforcement[- ]ladder\b",
        "The enforcement ladder is the default ladder here.",
    ),
    phrase(
        "default-ladder",
        r"\bresolution ladder\b",
        "The resolution ladder's default ladder tries npm first.",
    ),
    phrase(
        "default-ladder",
        r"\bmethod[- ]ladder\b",
        "The method ladder's default ladder tries gh first.",
    ),
    phrase(
        "default-ladder",
        r"\bcandidate ladder\b",
        "The candidate ladder's default ladder ranks skills first.",
    ),
    phrase(
        "overlay",
        r"\bpolicy[- ]overlays?\b",
        "The policy overlay layers on the shipped defaults.",
    ),
    phrase(
        "overlay",
        r"\bcatalog[- ]?overlays?\b",
        "The catalog overlay layers on the shipped catalog.",
    ),
    path(
        "overlay",
        "plugins/machine-health/skills/**",
        "plugins/machine-health/skills/check/SKILL.md",
        OVERLAY_LINE,
    ),
    path(
        "overlay",
        "plugins/machine-health/README.md",
        "plugins/machine-health/README.md",
        OVERLAY_LINE,
    ),
    path(
        "overlay",
        "plugins/user-interface/skills/**",
        "plugins/user-interface/skills/x/SKILL.md",
        OVERLAY_LINE,
    ),
    path(
        "overlay",
        "plugins/user-interface/reference/**",
        "plugins/user-interface/reference/x.md",
        OVERLAY_LINE,
    ),
    path(
        "overlay",
        "plugins/user-interface/evals/**",
        "plugins/user-interface/evals/x.md",
        OVERLAY_LINE,
    ),
    path(
        "overlay",
        "plugins/planning/shared/web/**",
        "plugins/planning/shared/web/page.css",
        OVERLAY_LINE,
    ),
    path(
        "overlay",
        "plugins/planning/evals/st-plan-4/graders/**",
        "plugins/planning/evals/st-plan-4/graders/defect-c.md",
        OVERLAY_LINE,
    ),
    path(
        "overlay",
        "plugins/playwright/skills/**",
        "plugins/playwright/skills/x/SKILL.md",
        OVERLAY_LINE,
    ),
    path(
        "overlay",
        "plugins/animation/skills/**",
        "plugins/animation/skills/x/SKILL.md",
        OVERLAY_LINE,
    ),
    path(
        "overlay",
        "plugins/pixel-art/reference/**",
        "plugins/pixel-art/reference/x.md",
        OVERLAY_LINE,
    ),
    path(
        "overlay",
        "plugins/pixel-art/skills/**",
        "plugins/pixel-art/skills/x/SKILL.md",
        OVERLAY_LINE,
    ),
    phrase(
        "overlay", r"\bbrand[- ]overlays?\b", "The brand overlay layers on the slide."
    ),
    path(
        "overlay",
        "plugins/ai-briefing/skills/generate/output/**",
        "plugins/ai-briefing/skills/generate/output/brief.md",
        OVERLAY_LINE,
    ),
    path("overlay", "plugins/gaming/**", "plugins/gaming/README.md", OVERLAY_LINE),
    path(
        "overlay",
        "plugins/songwriting/skills/**",
        "plugins/songwriting/skills/x/SKILL.md",
        OVERLAY_LINE,
    ),
    phrase(
        "overlay",
        r"\bagentic[- ]overlays?\b",
        "The agentic overlay layers on the harness.",
    ),
    phrase(
        "overlay",
        r"\b(css|ui|video|image|visual|modal)[- ]overlays?\b",
        "The modal overlay layers on the page.",
    ),
    phrase(
        "overlay",
        r"\badr/[0-9]{4}-[a-z0-9-]*overlay[a-z0-9-]*\.md\b",
        "Read [ADR 0015](../../adr/0015-bind-the-tracker-with-a-personal-overlay.md) on the layer.",
    ),
    *eval_rows("overlay", OVERLAY_LINE),
    path(
        "overlay",
        "plugins/disk-hygiene/skills/clean/**",
        "plugins/disk-hygiene/skills/clean/SKILL.md",
        OVERLAY_LINE,
    ),
    path(
        "overlay",
        "plugins/songwriting/context/**",
        "plugins/songwriting/context/x.md",
        OVERLAY_LINE,
    ),
    phrase(
        "tier-precedence",
        r"\bview tiers?\b",
        "The view tier overrides the page default.",
    ),
    phrase(
        "tier-precedence",
        r"\b(static|client-interactive|animated|claude-interactive) tiers?\b",
        "The static tier overrides the page default.",
    ),
    phrase(
        "tier-precedence",
        r"\benforcement[- ]ladder\b",
        "The enforcement ladder tier overrides the default.",
    ),
    path(
        "tier-precedence",
        "docs/contracts/enforcement-ladder/**",
        "docs/contracts/enforcement-ladder/v1.md",
        TIER_LINE,
    ),
    path(
        "tier-precedence",
        "docs/conventions/enforcement-ladder/**",
        "docs/conventions/enforcement-ladder/README.md",
        TIER_LINE,
    ),
    path(
        "tier-precedence",
        "**/enforcement-ladder.md",
        "docs/enforcement-ladder.md",
        TIER_LINE,
    ),
    phrase(
        "tier-precedence",
        r"\bmemory[- ]tiers?\b",
        "The memory tier overrides the default.",
    ),
    phrase(
        "tier-precedence",
        r"\b(model|strong|frontier|capability|cheap|fast)(:`)?[- ]tiers?\b|\bmodel:<tier>",
        "The model tier overrides the default.",
    ),
    *eval_rows("tier-precedence", TIER_LINE),
    phrase(
        "tier-precedence",
        r"\benterprise-tier keys\b",
        "Enterprise-tier keys override the limit.",
    ),
    phrase(
        "tier-precedence",
        r"\btiers?[- ](?:[0-9]|(?-i:[A-D])\b)",
        "Tier 2 overrides the default.",
    ),
    phrase(
        "tier-precedence",
        r"\bconsumer[- ]precedence\b",
        "The severity tier follows the consumer-precedence rule.",
    ),
    path(
        "tier-precedence",
        "docs/contracts/detector-findings/**",
        "docs/contracts/detector-findings/README.md",
        TIER_LINE,
    ),
    path(
        "tier-precedence",
        "plugins/review/context/severity.md",
        "plugins/review/context/severity.md",
        TIER_LINE,
    ),
    phrase(
        "tier-precedence",
        r"\beffort-tiers\b",
        "A pin overrides it through the [override levers](#effort-tiers).",
    ),
    phrase(
        "tier-precedence",
        r"\bmanaged[- ]tier\b",
        "Within the managed tier, read the precedence per file.",
    ),
    phrase(
        "tier-precedence",
        r"\bmods?\b.*\btiers?\b|\btiers?\b.*\bmods?\b",
        "A user-tier mod hears toasts.",
    ),
    path(
        "tier-precedence",
        "plugins/harness-ops/skills/audit-mod-posture/**",
        "plugins/harness-ops/skills/audit-mod-posture/SKILL.md",
        TIER_LINE,
    ),
    phrase(
        "tier-precedence",
        r"\bautonomy[- ]tiers?\b",
        "The session-only autonomy-tier override applies.",
    ),
    phrase(
        "tier-precedence",
        r"\bbabysit-prs tier\b",
        "A babysit-prs tier name overrides dimension 1.",
    ),
    path(
        "tier-precedence",
        "plugins/source-control/skills/babysit-*/**",
        "plugins/source-control/skills/babysit-prs/SKILL.md",
        TIER_LINE,
    ),
    path(
        "tier-precedence",
        "plugins/discipline/**",
        "plugins/discipline/README.md",
        TIER_LINE,
    ),
    phrase(
        "tier-precedence",
        r"^\s*local\s+(\w+(=\S*)?\s+)*tier\b",
        '  local tier reason pr_line="none"',
    ),
    path(
        "tier-precedence",
        "plugins/docs-naming/**",
        "plugins/docs-naming/README.md",
        TIER_LINE,
    ),
    phrase(
        "tier-precedence",
        r"`tiers`",
        "A policy-floor class on `tiers` overrides the default.",
    ),
    path(
        "tier-precedence",
        "plugins/repo-hygiene/skills/clean/**",
        "plugins/repo-hygiene/skills/clean/SKILL.md",
        TIER_LINE,
    ),
    phrase(
        "tier-precedence",
        r"\btrust tiers?\b",
        "Trust tiers: repo conventions override both.",
    ),
    path(
        "tier-precedence",
        "plugins/performance/skills/target/SKILL.md",
        "plugins/performance/skills/target/SKILL.md",
        TIER_LINE,
    ),
    phrase(
        "tier-precedence",
        r"\bone tier: Minor\b",
        "The response names one tier: Minor, Moderate or Major, which overrides.",
    ),
    path(
        "tier-precedence",
        "plugins/work-items/reference/pipeline-shape.md",
        "plugins/work-items/reference/pipeline-shape.md",
        TIER_LINE,
    ),
    phrase(
        "surface-config",
        r"\binterview surfaces?\b",
        "The interview surface reads settings.json.",
    ),
    phrase(
        "surface-config",
        r"\b(terminal|shared session)\b",
        "The terminal surface reads settings.json.",
    ),
    path(
        "surface-config",
        "plugins/planning/surface/**",
        "plugins/planning/surface/README.md",
        SURFACE_LINE,
    ),
    phrase(
        "surface-config",
        r"\bplanning/surface\b",
        "The planning/surface code reads settings.json.",
    ),
    phrase(
        "surface-config",
        r"\b(skills?|commands?)\b.*\bsurfaces?\b|\bsurfaces?\b.*\b(skills?|commands?)\b",
        "Each surface reads its skills from settings.json.",
    ),
    phrase(
        "surface-config",
        r"\bemitting surfaces?\b",
        "The emitting surface reads settings.json.",
    ),
    *eval_rows("surface-config", SURFACE_LINE),
    phrase(
        "surface-config",
        r"\bshop surface is http\b",
        "The shop surface is http://127.0.0.1:8080 in config.yaml.",
    ),
    phrase(
        "surface-config",
        r"\bsettings surfaces?\b.*\b(ladder|fetched docs?|UI-only)\b|\b(ladder|UI-only)\b.*\bsettings surfaces?\b",
        "The UI-only step names the exact settings surface.",
    ),
    phrase(
        "surface-config",
        r"\bsettings surfaces a non-zero exit\b",
        "Bad settings surfaces a non-zero exit.",
    ),
    phrase(
        "surface-config",
        r"\b(memory-layer|instruction) surfaces?\b",
        "On memory-layer surfaces such as CLAUDE.local.md, read settings.json too.",
    ),
    phrase(
        "surface-config",
        r"\brunnable surfaces?\b",
        "A live run for any change with a runnable surface in settings.json.",
    ),
    phrase(
        "surface-config",
        r"\b(trust|attack|telemetry|launch|escape) surfaces?\b|\bPATH surfaces\b",
        "The added trust surface is that settings.json read.",
    ),
    path(
        "surface-config",
        "docs/contracts/standards/**",
        "docs/contracts/standards/README.md",
        SURFACE_LINE,
    ),
    path(
        "surface-config",
        "**/standards-contract.md",
        "plugins/review/reference/standards-contract.md",
        SURFACE_LINE,
    ),
    phrase(
        "surface-config",
        r"`surfaces`",
        "The concern file is `docs/conventions/standards.yaml`; entries take `surfaces` in place of `topics`.",
    ),
    phrase(
        "surface-config",
        r"\bsurface,?\s+(or|and|checker or)\s+(supplying\s+)?settings files?\b",
        "It refuses a surface, checker or supplying settings file.",
    ),
    phrase(
        "surface-config",
        r"##\s*Surfaces\b|\bthe surfaces `lens` runs\b",
        "Say so in the report's ## Surfaces for settings.json.",
    ),
    path(
        "surface-config",
        "plugins/harness-config/skills/audit-permission-state/**",
        "plugins/harness-config/skills/audit-permission-state/SKILL.md",
        SURFACE_LINE,
    ),
    path(
        "surface-config",
        "plugins/harness-config/schemas/harness-config.schema.json",
        "plugins/harness-config/schemas/harness-config.schema.json",
        SURFACE_LINE,
    ),
    path(
        "surface-config",
        "plugins/harness-config/skills/audit/scripts/**",
        "plugins/harness-config/skills/audit/scripts/x.sh",
        SURFACE_LINE,
    ),
    phrase(
        "contract-brief",
        r"\bdocs/contracts\b|\bcontracts/[\w-]+|\bversioned contracts?\b",
        "The Brief cites docs/contracts/loop-lane.",
    ),
    phrase(
        "contract-brief",
        r"\binterface contracts?\b",
        "The Brief names an interface contract.",
    ),
    phrase(
        "contract-brief",
        r"\b(pr|api|feed|payload|behavioral|presentation|execution|detection|return|framing|findings)[- ]contracts?\b",
        "The dispatch brief carries the PR contract forward.",
    ),
    phrase(
        "contract-brief",
        r"\bname[- ]by[- ]contract\b",
        "The brief follows the name-by-contract rule.",
    ),
    phrase(
        "contract-brief",
        r"\bissue-body contract\b",
        "The brief's fields are the agent-ready type of the issue-body contract.",
    ),
    phrase(
        "contract-brief",
        r"\bcontract case\b",
        "Contract case for the hand-off once the Brief is locked.",
    ),
    *eval_rows("contract-brief", CONTRACT_LINE),
    path(
        "contract-brief",
        "plugins/implementation/agents/*.md",
        "plugins/implementation/agents/implementer.md",
        CONTRACT_LINE,
    ),
    phrase(
        "contract-brief",
        r'\|\s*contract\s*\|\s*name\s*\||\("contract",',
        "| contract | name | `BRIEF*` |",
    ),
    phrase(
        "contract-brief",
        r"\bparent-contract\b",
        "The Brief links reference/parent-contract.md.",
    ),
    phrase(
        "contract-brief",
        r"\bmodule layout, contracts\b",
        "The brief quotes its module layout, contracts and verdicts.",
    ),
    phrase(
        "contract-brief",
        r"\bworker specs as contracts\b",
        "The brief writes worker specs as contracts.",
    ),
    path(
        "lane-hunt-scope",
        ".changes/**",
        ".changes/code-tidying/rename.md",
        "Move any `.claude/tidy-lanes/` files to `.claude/tidy-areas/`.",
    ),
    path(
        "lane-view-producer",
        "**/evals/**/samples/**",
        "plugins/alpha/evals/one/samples/answer.json",
        "node lib/view-settings.mjs resolve --lane planning --option auto",
    ),
    path(
        "lane-view-producer",
        "**/evals/**/graders/**",
        "plugins/alpha/evals/one/graders/check.md",
        "node lib/view-settings.mjs resolve --lane planning --option auto",
    ),
    phrase(
        "lane-view-producer",
        r"""^\s*(?:-\s*)?pattern:\s*['"]""",
        'pattern: "node lib/view-settings.mjs resolve --lane planning --option auto"',
    ),
    path(
        "lane-view-producer",
        "plugins/testing/skills/audit/evals/judge-calibration/**",
        "plugins/testing/skills/audit/evals/judge-calibration/cases/copy.py",
        "node lib/view-settings.mjs resolve --lane planning --option auto",
    ),
    path(
        "lane-placement-direction",
        "**/evals/**/samples/**",
        "plugins/alpha/evals/one/samples/answer.json",
        "Flag stranded docs conventions on the promote lane.",
    ),
    path(
        "lane-placement-direction",
        "plugins/testing/skills/audit/evals/judge-calibration/**",
        "plugins/testing/skills/audit/evals/judge-calibration/cases/copy.py",
        "Flag stranded docs conventions on the promote lane.",
    ),
    path(
        "lane-code-metrics-language",
        "**/evals/**/samples/**",
        "plugins/alpha/evals/one/samples/answer.json",
        "Files outside every language lane carry a line count.",
    ),
    path(
        "lane-code-metrics-language",
        "plugins/testing/skills/audit/evals/judge-calibration/**",
        "plugins/testing/skills/audit/evals/judge-calibration/cases/copy.py",
        "Files outside every language lane carry a line count.",
    ),
    path(
        "lane-dead-code-analyzer",
        "**/evals/**/samples/**",
        "plugins/alpha/evals/one/samples/answer.json",
        "Run dead-code-scan.sh --lane grep over src.",
    ),
    path(
        "lane-dead-code-analyzer",
        "plugins/testing/skills/audit/evals/judge-calibration/**",
        "plugins/testing/skills/audit/evals/judge-calibration/cases/copy.py",
        "Run dead-code-scan.sh --lane grep over src.",
    ),
    path(
        "lane-coupling-step",
        "**/evals/**/samples/**",
        "plugins/alpha/evals/one/samples/answer.json",
        "A second list is always a route-lane ledger entry.",
    ),
    path(
        "lane-coupling-step",
        "plugins/testing/skills/audit/evals/judge-calibration/**",
        "plugins/testing/skills/audit/evals/judge-calibration/cases/copy.py",
        "A second list is always a route-lane ledger entry.",
    ),
    path(
        "lane-owning-skill",
        "**/evals/**/samples/**",
        "plugins/alpha/evals/one/samples/answer.json",
        "Hand the findings off to the remediation lanes.",
    ),
    path(
        "lane-owning-skill",
        "plugins/testing/skills/audit/evals/judge-calibration/**",
        "plugins/testing/skills/audit/evals/judge-calibration/cases/copy.py",
        "Hand the findings off to the remediation lanes.",
    ),
    path(
        "lane-view-producer",
        ".changes/**",
        ".changes/code-tidying/rename.md",
        "Run `view-settings.mjs resolve --producer <id>` (`--lane` is gone).",
    ),
    path(
        "lane-placement-direction",
        ".changes/**",
        ".changes/code-tidying/rename.md",
        "It takes `--direction demote|promote` (`--lane` is gone).",
    ),
    path(
        "lane-code-metrics-language",
        ".changes/**",
        ".changes/code-tidying/rename.md",
        "`scripts/detect-lanes.sh` is `scripts/detect-languages.sh`.",
    ),
    path(
        "lane-dead-code-analyzer",
        ".changes/**",
        ".changes/code-tidying/rename.md",
        "Run `dead-code-scan.sh --analyzer <name>` (`--lane` is gone).",
    ),
    path(
        "lane-dead-code-analyzer",
        "plugins/code-tidying/skills/audit-dead-code/evals/fixtures/**",
        "plugins/code-tidying/skills/audit-dead-code/evals/fixtures/standalone.mjs",
        "// Standalone-module control for the grep lane.",
    ),
    path(
        "lane-hunt-scope",
        "plugins/evals/skills/plugin-eval/scripts/test_select_cases_no_run.py",
        "plugins/evals/skills/plugin-eval/scripts/test_select_cases_no_run.py",
        "Hunt one rotated lane at a time.",
    ),
]
