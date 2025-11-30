# Best Practices for Markdown Linting

## For Writing Markdown

1. **Run linting early and often** - Check with npx or npm scripts before committing
2. **Enable auto-fix on save** - Configure VS Code to fix issues automatically (optional)
3. **Learn common rules** - Familiarize yourself with frequently violated rules
4. **Use the VS Code extension** - Real-time feedback prevents accumulating errors (optional)
5. **Fix content, not rules** - Always try to fix the markdown first before relaxing rules

## For Configuration Management

1. **Think carefully before changing rules** - Rules exist for good reasons (quality, accessibility, consistency)
2. **Document rule changes** - Explain rationale in commit messages
3. **Test locally first** - Before pushing config changes, verify with linting commands
4. **Keep configuration portable** - Use `.markdownlint-cli2.jsonc` in project root, avoid user-specific settings
5. **Maintain consistency** - Same rules across all markdown files in the project

## For Collaboration

1. **Pre-commit checks** - Always run linting (npx or npm scripts) before pushing
2. **Fix CI failures promptly** - Don't ignore CI/CD linting failures (if configured)
3. **Don't disable rules to pass CI** - Fix the content instead
4. **Document exceptions** - If rule relaxation is needed, note why in commit/PR description
5. **Share knowledge** - Help team members understand linting rules and rationale

## For Skill Automation (Claude Code Usage)

1. **Always validate before suggesting changes** - Run linting commands to verify
2. **Automatically fix ALL errors** - When running linting, ALWAYS automatically:
   - Run `--fix` flag for auto-fixable errors
   - Intelligently analyze and fix "unfixable" errors (MD024, MD001, MD051, etc.) using context-aware fixes
   - DO NOT ask for confirmation or approval - just fix everything automatically
3. **Intelligent fix application** - For "unfixable" errors:
   - Read affected files to understand context
   - Analyze error and surrounding content
   - Apply appropriate fixes based on context (see "Intelligent Fix Handling" section in SKILL.md)
   - Re-run linting to verify all fixes
4. **Manual editing required** - Use Edit tool for precise changes, NEVER use scripts for linting fixes
5. **Use parallel Task agents for efficiency** - Launch multiple agents in parallel when fixing errors across many files
6. **Explain rule violations** - Help users understand WHY something violates a rule
7. **Respect configuration** - Don't modify `.markdownlint-cli2.jsonc` without understanding project policy
8. **Link to official docs** - Provide rule documentation links for complex violations

### When to use parallel Task agents

- **High-error files (20+ errors)**: Launch one agent per file
- **Medium-error files (10-20 errors)**: Launch one agent per file
- **Low-error files (1-9 errors)**: Group into batches, one agent per file
- **Large repositories**: Parallelize across files to maximize efficiency

Each Task agent should:

- Run linter to identify specific errors in their assigned file
- Read the file to understand context
- Use Edit tool to fix ALL errors manually (no scripts)
- Re-run linter to verify all errors are fixed
- Report summary of fixes applied

---

**Last Verified**: 2025-11-25
