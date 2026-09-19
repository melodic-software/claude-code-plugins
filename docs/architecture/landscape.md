# System Landscape

Generated on 2026-09-19 from current repository plus reference graph. Remote facts: not used.

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
  System_Ext(crate_ci_typos, "crate-ci/typos", "not checked out here")
  System_Ext(Dometrain_mcp, "Dometrain/mcp", "not checked out here")
  System_Ext(koalaman_shellcheck, "koalaman/shellcheck", "not checked out here")

  Rel(melodic_software_claude_code_plugins, Dometrain_mcp, "cites (8)")
  Rel(melodic_software_claude_code_plugins, anthropics_claude_code, "cites (38)")
  Rel(melodic_software_claude_code_plugins, crate_ci_typos, "cites (9)")
  Rel(melodic_software_claude_code_plugins, koalaman_shellcheck, "cites (7)")
  Rel(melodic_software_claude_code_plugins, melodic_software_ci_workflows, "cites (126)")
  Rel(melodic_software_claude_code_plugins, melodic_software_claude_code_plugins_ci, "cites (1)")
  Rel(melodic_software_claude_code_plugins, melodic_software_dotfiles, "cites (4)")
  Rel(melodic_software_claude_code_plugins, melodic_software_github_iac, "cites (18)")
  Rel(melodic_software_claude_code_plugins, melodic_software_knowledge_corpus, "cites (2)")
  Rel(melodic_software_claude_code_plugins, melodic_software_medley, "cites (16)")
  Rel(melodic_software_claude_code_plugins, melodic_software_miro_mcp, "cites (1)")
  Rel(melodic_software_claude_code_plugins, melodic_software_provisioning, "cites (5)")
  Rel(melodic_software_claude_code_plugins, melodic_software_runner_policy_runtime, "cites (1)")
  Rel(melodic_software_claude_code_plugins, melodic_software_standards, "cites (53)")
  Rel(melodic_software_claude_code_plugins, actions_checkout, "uses-workflow (10)")
  Rel(melodic_software_claude_code_plugins, melodic_software_ci_workflows, "uses-workflow (22)")
```

66 external repositories are referenced but not drawn; the record carries
every one of them.
