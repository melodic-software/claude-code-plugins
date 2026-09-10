# System Landscape

Generated on 2026-09-10 from current repository plus reference graph. Remote facts: not used.

Every fact traces to the file the probe named. Every edge is typed by the
syntax that carries it and labelled with how many references support it.
A system with no probed runtime is one this checkout names but does not
contain.

```mermaid
C4Context
  title System Landscape
  Enterprise_Boundary(b0, "melodic-software") {
    System(melodic_software_ci_workflows, "ci-workflows", "not checked out here")
    System(melodic_software_claude_code_plugins, "claude-code-plugins", "shell")
    System(melodic_software_claude_code_plugins_ci, "claude-code-plugins-ci", "not checked out here")
    System(melodic_software_dotfiles, "dotfiles", "not checked out here")
    System(melodic_software_github_iac, "github-iac", "not checked out here")
    System(melodic_software_knowledge_corpus, "knowledge-corpus", "not checked out here")
    System(melodic_software_medley, "medley", "not checked out here")
    System(melodic_software_miro_mcp, "miro-mcp", "not checked out here")
    System(melodic_software_provisioning, "provisioning", "not checked out here")
    System(melodic_software_runner_policy_runtime, "runner-policy-runtime", "not checked out here")
    System(melodic_software_standards, "standards", "not checked out here")
  }
  System_Ext(anthropics_claude_code, "anthropics/claude-code", "not checked out here")
  System_Ext(actions_checkout, "actions/checkout", "not checked out here")

  Rel(melodic_software_claude_code_plugins, anthropics_claude_code, "cites (37)")
  Rel(melodic_software_claude_code_plugins, melodic_software_ci_workflows, "cites (142)")
  Rel(melodic_software_claude_code_plugins, melodic_software_claude_code_plugins_ci, "cites (1)")
  Rel(melodic_software_claude_code_plugins, melodic_software_dotfiles, "cites (4)")
  Rel(melodic_software_claude_code_plugins, melodic_software_github_iac, "cites (18)")
  Rel(melodic_software_claude_code_plugins, melodic_software_knowledge_corpus, "cites (2)")
  Rel(melodic_software_claude_code_plugins, melodic_software_medley, "cites (17)")
  Rel(melodic_software_claude_code_plugins, melodic_software_miro_mcp, "cites (1)")
  Rel(melodic_software_claude_code_plugins, melodic_software_provisioning, "cites (5)")
  Rel(melodic_software_claude_code_plugins, melodic_software_runner_policy_runtime, "cites (1)")
  Rel(melodic_software_claude_code_plugins, melodic_software_standards, "cites (53)")
  Rel(melodic_software_claude_code_plugins, actions_checkout, "uses-workflow (15)")
  Rel(melodic_software_claude_code_plugins, melodic_software_ci_workflows, "uses-workflow (24)")
```

63 external repositories are referenced but not drawn; the record carries
every one of them.

## Annotations

Everything above is extracted. Everything here is annotation: the extractor reports
that a repository is referenced and how, never what it is for. Edit this file
freely; the renderer appends it and never overwrites it.

| System | What it is for |
|---|---|
| `claude-code-plugins` | This repository. The plugin marketplace and its skills. |
| `ci-workflows` | The reusable workflows and composite actions every lane here calls. |
| `standards` | The engineering conventions this repository restates and defers to. |
| `github-iac` | GitHub organisation and repository configuration as code. |
| `medley` | An application repository that consumes these plugins. |
| `provisioning` | Machine provisioning. |
| `dotfiles` | Developer environment setup. |
| `knowledge-corpus` | Source material the writing and research skills draw on. |
| `anthropics/claude-code` | The CLI these plugins target. External, read-only. |
| `actions/checkout` | The GitHub Action every workflow here starts with. External, read-only. |

The `cites` counts dwarf every other edge type because this repository is mostly
prose about tooling. A high `cites` count means the two repositories talk about
each other, not that one runs on the other. `uses-workflow` is the edge that
carries a real runtime dependency.
