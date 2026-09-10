# System Landscape

Generated on 2026-09-10 from this repository plus its reference graph, one hop
out. Facts come from `portfolio-facts.sh`; edges come from `reference-edges.sh`,
which reads tracked files only. Nothing was fetched, so a stale checkout reports
a stale date and a repository this one never names does not appear at all.

Every edge is typed by the syntax that carries it and labelled with how many
references support it. `uses-workflow` is a workflow step this repository runs.
`cites` is the weakest type: a mention in prose, configuration, or a rule.

```mermaid
C4Context
  title System Landscape
  Enterprise_Boundary(b0, "melodic-software") {
    System(claude_code_plugins, "claude-code-plugins", "shell; tooling: node, python")
    System(ci_workflows, "ci-workflows", "reusable CI workflows")
    System(standards, "standards", "engineering conventions")
    System(github_iac, "github-iac", "GitHub configuration as code")
    System(medley, "medley", "application")
    System(provisioning, "provisioning", "machine provisioning")
    System(dotfiles, "dotfiles", "developer environment")
  }
  System_Ext(anthropics_claude_code, "anthropics/claude-code", "the CLI these plugins target")
  System_Ext(actions_checkout, "actions/checkout", "GitHub Action")

  Rel(claude_code_plugins, ci_workflows, "uses-workflow (24)")
  Rel(claude_code_plugins, ci_workflows, "cites (142)")
  Rel(claude_code_plugins, standards, "cites (53)")
  Rel(claude_code_plugins, github_iac, "cites (18)")
  Rel(claude_code_plugins, medley, "cites (17)")
  Rel(claude_code_plugins, provisioning, "cites (5)")
  Rel(claude_code_plugins, dotfiles, "cites (4)")
  Rel(claude_code_plugins, anthropics_claude_code, "cites (37)")
  Rel(claude_code_plugins, actions_checkout, "uses-workflow (15)")
```

## What the diagram leaves out

Five further same-owner repositories are referenced once or twice each and are
omitted to keep the diagram readable: `knowledge-corpus` (2), plus
`runner-policy-runtime`, `miro-mcp`, and `claude-code-plugins-ci` (1 each).

Sixty-five external repositories are referenced in total. Only the two most
referenced are drawn. The rest are tool and documentation citations rather than
systems this repository relates to, and they belong in the record instead of the
diagram.

Node descriptions above are annotations, not extracted facts: the extractor
reports that a repository is referenced and how, never what it is for. Only the
`claude-code-plugins` node carries probe-derived runtime and tooling, because it
is the only repository checked out here.
