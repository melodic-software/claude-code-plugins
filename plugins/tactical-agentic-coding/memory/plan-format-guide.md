# Plan Format Guide

Standard plan structures for different types of engineering work. Plans are written to `specs/*.md`.

## Why Plan Formats Matter

Consistent plan formats enable:

- **Predictable execution**: Agents know what to expect
- **Quality standards**: Every plan covers essential sections
- **Team alignment**: Everyone uses the same structure
- **Validation**: Built-in verification in every plan

## Chore Plan Format

For maintenance tasks, refactoring, updates, and cleanup work.

```markdown
# Chore: <descriptive-name>

## Chore Description
<Clear explanation of what needs to be done and why>

## Relevant Files
<List of files that will be created, modified, or deleted>

## Step by Step Tasks
1. <First specific task>
2. <Second specific task>
3. <Continue with numbered tasks>

## Validation Commands
<Commands that verify the work is complete>
- Run `<command>` to verify <what>
- Check `<file>` for <expected state>

## Notes
<Edge cases, dependencies, gotchas, related work>
```markdown

### Example Chore Plan

```markdown
# Chore: Update Python Dependencies

## Chore Description
Update all Python dependencies to their latest compatible versions
and verify the application still works correctly.

## Relevant Files
- pyproject.toml
- uv.lock
- requirements.txt (if exists)

## Step by Step Tasks
1. Run `uv lock --upgrade` to update lock file
2. Review changes in uv.lock for major version bumps
3. Run test suite to verify compatibility
4. Update any deprecated API usages if tests fail
5. Commit changes with descriptive message

## Validation Commands
- Run `uv sync` to verify dependencies install
- Run `pytest tests/` to verify all tests pass
- Run `ruff check .` to verify no linting errors

## Notes
- Check CHANGELOG of any major version updates
- Pay attention to breaking changes in critical dependencies
```markdown

## Bug Plan Format

For investigating and fixing bugs. Includes root cause analysis.

```markdown
# Bug: <descriptive-name>

## Bug Description
<Clear explanation of the bug and its impact>

## Problem Statement
<What is happening that should not be happening>

## Solution Statement
<What should happen instead>

## Steps to Reproduce
1. <Step to reproduce>
2. <Continue steps>
3. <Expected vs actual result>

## Root Cause Analysis
<Investigation findings - why is this happening>

## Relevant Files
<Files involved in the bug and fix>

## Step by Step Tasks
1. <First fix task>
2. <Continue with numbered tasks>

## Validation Commands
<Commands that verify the bug is fixed>
- Run `<test>` to verify fix
- Reproduce steps above to confirm resolution

## Notes
<Related bugs, regression risks, areas to monitor>
```markdown

### Example Bug Plan

```markdown
# Bug: Login Form Submits Twice on Enter

## Bug Description
Pressing Enter in the login form submits the form twice,
causing duplicate API calls and occasional race conditions.

## Problem Statement
Form submission triggers twice when Enter key is pressed,
resulting in duplicate POST requests to /api/auth/login.

## Solution Statement
Form should submit exactly once per Enter press or button click.

## Steps to Reproduce
1. Navigate to /login
2. Enter valid credentials
3. Press Enter key
4. Observe Network tab: two POST requests to /api/auth/login
5. Expected: one request. Actual: two requests.

## Root Cause Analysis
The form has both an onSubmit handler and an onClick handler
on the submit button. When Enter is pressed, both fire.

## Relevant Files
- src/components/LoginForm.tsx
- src/hooks/useAuth.ts

## Step by Step Tasks
1. Remove onClick handler from submit button
2. Ensure onSubmit handles all submission logic
3. Add form submission debounce as safety net
4. Add test for single-submission behavior

## Validation Commands
- Run `npm test -- LoginForm` to verify component tests pass
- Manually test: Enter key should trigger one request
- Check Network tab confirms single POST

## Notes
- Check other forms for similar pattern
- Consider adding global form submission tracking
```markdown

## Feature Plan Format

For new functionality. Includes user story and testing strategy.

```markdown
# Feature: <descriptive-name>

## Feature Description
<Clear explanation of the feature and its value>

## User Story
As a <role>, I want <capability> so that <benefit>.

## Problem Statement
<What user need or pain point does this address>

## Solution Statement
<High-level description of how this solves the problem>

## Relevant Files
<Files to create or modify>

## Implementation Plan

### Foundation Phase
<Setup, dependencies, configuration>

### Core Phase
<Main feature implementation>

### Integration Phase
<Connecting components, final wiring>

## Step by Step Tasks
1. <First task>
2. <Continue with numbered tasks>

## Testing Strategy

### Unit Tests
<Component and function-level tests>

### Integration Tests
<Cross-component and API tests>

### Edge Cases
<Boundary conditions and error scenarios>

## Acceptance Criteria
- [ ] <Criterion 1>
- [ ] <Criterion 2>
- [ ] <Continue criteria>

## Validation Commands
- Run `<test suite>` to verify all tests pass
- Run `<build command>` to verify build succeeds
- Manual verification: <steps>

## Notes
<Future enhancements, related features, technical debt>
```markdown

### Example Feature Plan

```markdown
# Feature: Dark Mode Toggle

## Feature Description
Add a dark mode toggle to the settings page that persists
user preference and respects system settings.

## User Story
As a user, I want to switch to dark mode so that I can
reduce eye strain when using the app at night.

## Problem Statement
Users have no way to change the color scheme, making the
app uncomfortable to use in low-light environments.

## Solution Statement
Add a theme toggle in settings with three options: Light,
Dark, and System. Persist preference in localStorage.

## Relevant Files
- src/contexts/ThemeContext.tsx (create)
- src/components/Settings/ThemeToggle.tsx (create)
- src/styles/themes/dark.css (create)
- src/styles/themes/light.css (modify)
- src/App.tsx (modify)

## Implementation Plan

### Foundation Phase
- Create ThemeContext with light/dark/system values
- Set up CSS custom properties for theming
- Create theme CSS files

### Core Phase
- Implement ThemeProvider wrapper
- Create ThemeToggle component
- Add localStorage persistence

### Integration Phase
- Wrap App in ThemeProvider
- Add ThemeToggle to Settings page
- Apply theme class to document root

## Step by Step Tasks
1. Create ThemeContext with createContext and useContext
2. Define CSS custom properties in :root
3. Create dark.css with dark theme values
4. Implement ThemeProvider with localStorage sync
5. Create ThemeToggle with three options
6. Add system preference detection (prefers-color-scheme)
7. Integrate into Settings page
8. Add transition effects for smooth switching

## Testing Strategy

### Unit Tests
- ThemeContext provides correct default
- ThemeToggle renders three options
- Theme changes update document class

### Integration Tests
- Theme persists across page reload
- System preference respected on first load

### Edge Cases
- localStorage unavailable (fallback to system)
- Invalid stored value (fallback to system)

## Acceptance Criteria
- [ ] Toggle visible in Settings page
- [ ] Three options: Light, Dark, System
- [ ] Theme changes immediately on selection
- [ ] Preference persists across sessions
- [ ] System option follows OS setting

## Validation Commands
- Run `npm test` to verify all tests pass
- Run `npm run build` to verify build succeeds
- Manual: Toggle each option, verify colors change
- Manual: Reload page, verify preference persists

## Notes
- Consider adding per-component theme support later
- Dark mode for code blocks may need syntax theme swap
```markdown

## Output Location

All plans should be written to the `specs/` directory:

```text
specs/
  chore-update-dependencies.md
  bug-login-double-submit.md
  feature-dark-mode.md
```markdown

This keeps plans organized and separate from implementation code.

## Related Memory Files

- @template-engineering.md - How to create templates that generate these plans
- @meta-prompt-patterns.md - Prompt hierarchy and composition
- @fresh-agent-rationale.md - Why use fresh agents for plan vs implement
