# Documentation Rules

Comprehensive documentation quality standards for *.md file reviews. Enforces CLAUDE.md documentation quality requirements.

## Required Documentation Elements

### Official Documentation Links

- [ ] Every platform-specific setup guide includes "Official Documentation" link
- [ ] Format: `**Official Documentation:** [Tool Name Official Docs](URL)`
- [ ] Links point to canonical vendor documentation (not third-party tutorials)
- [ ] Links verified and not broken

**Detection:** Search for "Official Documentation:" heading in setup guides

**Rationale:** Establishes authoritative source and enables users to verify independently

### Version Information

- [ ] Specify minimum versions required
- [ ] Note LTS vs latest where applicable
- [ ] Document breaking changes if relevant
- [ ] Format example: `**Recommended Version:** Node.js 20.x LTS (current as of 2025-01)`

**Detection:** Look for version sections, check if minimum/recommended are specified

**Rationale:** Prevents compatibility issues and guides version selection

### Installation Steps

- [ ] Steps in dependency order (prerequisites installed first)
- [ ] Each command verified against official documentation
- [ ] Expected output included where helpful
- [ ] Clear separation between required and optional steps

**Detection:** Check step ordering against dependency hierarchy, verify commands match official docs

**Rationale:** Ensures successful installation by respecting dependency chains

### Verification Steps

- [ ] How to confirm installation succeeded
- [ ] Version check commands included
- [ ] Basic functionality test provided
- [ ] Expected output documented

**Example format:**

```markdown
## Verify Installation

\`\`\`bash
git --version
# Expected output: git version 2.43.0 (or newer)
\`\`\`
```

**Detection:** Search for "Verify Installation" or "Verification" sections

**Rationale:** Provides immediate feedback on installation success

### Troubleshooting Sections

- [ ] Link to official issue trackers
- [ ] Document common problems with solutions
- [ ] Reference official troubleshooting docs (no duplication)
- [ ] Platform-specific gotchas noted

**Detection:** Check for "Troubleshooting" sections

**Rationale:** Reduces support burden by documenting known issues upfront

### Last Verified Date

- [ ] Format: `**Last Verified:** YYYY-MM-DD`
- [ ] Include MCP server used if applicable: `(via Microsoft Learn MCP)`
- [ ] Date is recent (within past 6 months for active tools)

**Detection:** Search for "Last Verified:" in footer/header

**Rationale:** Helps identify stale content during maintenance cycles

## MCP Server Usage Requirements

### When Creating/Updating Guides

- [ ] Use `ref` or `firecrawl` MCP to fetch official documentation
- [ ] Use `microsoft-learn` MCP for Windows/WSL/Azure/PowerShell content
- [ ] Use `perplexity` MCP to cross-reference community best practices
- [ ] Use `context7` MCP for broader ecosystem context

**Detection:** Check git history for evidence of MCP usage (commit messages, documented research)

**Rationale:** Ensures documentation is backed by current, official sources

### Content Validation

- [ ] Every command validated against official sources
- [ ] Version compatibility checked via MCP servers
- [ ] Installation steps verified in order
- [ ] Troubleshooting steps current (not stale)

**Detection:** Cross-reference content with official docs (via MCP servers)

**Rationale:** Maintains accuracy and prevents propagation of outdated information

## Hub-and-Spoke Navigation Model

### Hub Files

- [ ] Brief overview only (no detailed content)
- [ ] Links to detailed topic files (spokes)
- [ ] No duplicated content from spokes
- [ ] Dependency ordering enforced (see architecture.md)

**Detection:** Check hub files for detailed content that belongs in spokes

**Rationale:** Separation of concerns - hub for navigation, spokes for details

### Spoke Files (Topic Files)

- [ ] Complete detailed instructions
- [ ] Self-contained (can be read independently)
- [ ] Referenced by hub with brief context
- [ ] Each topic exists in exactly ONE spoke

**Detection:** Verify each topic has single authoritative file

**Rationale:** Single source of truth for each topic

## Dependency Order Validation

### Installation Order Rules

- [ ] Package managers installed before tools
- [ ] WSL installed before WSL-dependent tools (Docker, Linux dev tools)
- [ ] Git installed before Git-dependent workflows (NVM, some installations)
- [ ] Runtime environments (Node.js, Python) before tools requiring them
- [ ] IDEs/editors last (depend on languages/runtimes)

**Detection:** Compare installation order against canonical dependency chain

**Rationale:** Prevents installation failures due to missing prerequisites

### Updating Hub Documents

- [ ] New tools placed in correct dependency order
- [ ] All platform hubs updated consistently (Windows, macOS, Linux, WSL)
- [ ] Rationale documented if order is non-obvious

**Detection:** Check that hub order matches dependency requirements

**Rationale:** Maintains consistent, working installation workflows across platforms

## Documentation Completeness Markers

### Status Indicators

- [ ] `> TBD` used for sections needing completion
- [ ] `#TODO: ...` used for items needing validation (with specific action)
- [ ] `**Last Verified:** ...` indicates validated content
- [ ] No unmarked incomplete sections

**Detection:** Search for TBD, TODO, and verify Last Verified dates are present

**Rationale:** Makes documentation status transparent and tracks validation

## Platform Variants

### When to Create Platform Variants

- [ ] Create `-windows.md`, `-macos.md`, `-linux.md` when content differs
- [ ] Or: Shared doc + platform supplements if 80%+ identical
- [ ] WSL variants default to redirecting to `-linux.md` unless WSL-specific differences exist

**Detection:** Check if platform content is split appropriately

**Rationale:** Avoids mixed platform content while preventing unnecessary duplication

### Platform Variant Consistency

- [ ] All platform variants have same structure/sections
- [ ] Version requirements documented per platform
- [ ] Platform-specific gotchas clearly noted

**Detection:** Compare structure across platform variant files

**Rationale:** Parallel structure reduces cognitive load and maintenance burden

## Common Documentation Violations

**High severity:**

1. Missing official documentation links
2. Missing verification steps
3. Wrong dependency order
4. Stale Last Verified dates (>6 months old)

**Medium severity:**

1. Missing version information
2. No troubleshooting section
3. Hub files containing detailed content (should be in spokes)

**Low severity:**

1. Missing MCP server attribution
2. Incomplete status markers
