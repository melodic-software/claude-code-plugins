# Distributing Skills Workflow

Step-by-step workflow for sharing and distributing Claude Code skills.

## Official Documentation Query

For complete distribution guidance, query docs-management:

```text
Find documentation about skill distribution using keywords: skill distribution, plugin skills, personal skills, project skills
```

## Workflow Overview

**High-Level Steps:**

1. **Choose Distribution Method** → Personal, Project, or Plugin
2. **Prepare Skill** → Validate and document
3. **Setup Distribution** → Configure location
4. **Test Distribution** → Verify accessibility
5. **Maintain Skill** → Update and support

## Distribution Options

### Option 1: Personal Skills

**Location:** `~/.claude/skills/[skill-name]/`

Query docs-management: "Find personal skills configuration and setup"

**Use When:**

- Individual use only
- Not team-shared
- Available across all your projects

### Option 2: Project Skills

**Location:** `.claude/skills/[skill-name]/`

Query docs-management: "Find project skills configuration and git distribution"

**Use When:**

- Team collaboration
- Version controlled
- Project-specific

### Option 3: Plugin Skills

Query docs-management: "Find plugin creation and skills distribution via plugins"

**Use When:**

- Public distribution
- Marketplace sharing
- Broad audience

## Detailed Workflow

### Step 1: Choose Distribution Method

Query docs-management: "Find skill distribution options and when to use each"

**Decision Tree:**

1. Only you will use it → Personal skills
2. Team will use it → Project skills (git)
3. Public sharing → Plugin skills (marketplace)

### Step 2: Prepare Skill

Query docs-management: "Find skill preparation and quality standards for distribution"

**Validate:**

- YAML frontmatter correct
- Examples are clear
- Documentation complete
- Tests pass
- Version history documented

### Step 3: Setup Distribution

**For Project Skills (Git):**

```bash
# Place in .claude/skills/
git add .claude/skills/[skill-name]
git commit -m "Add [skill-name] skill"
git push
```

**For Personal Skills:**

```bash
# Copy to personal skills directory
cp -r .claude/skills/[skill-name] ~/.claude/skills/
```

**For Plugin Skills:**
Query docs-management: "Find plugin creation and publication workflow"

### Step 4: Test Distribution

**Verify:**

- Skill appears in skill list
- Skill activates correctly
- Team members can access (if project skill)
- Installation works (if plugin)

### Step 5: Maintain Skill

Query docs-management: "Find skill maintenance best practices"

**Ongoing:**

- Update version history
- Fix issues reported
- Enhance based on feedback
- Keep dependencies current

## Common Queries

**For personal skills setup:**
**Query docs-management:** "Find personal skills directory configuration and installation"

**For project skills git workflow:**
**Query docs-management:** "Find project skills git distribution and team collaboration"

**For plugin creation:**
**Query docs-management:** "Find plugin skills creation, packaging, and marketplace distribution"

**For skill maintenance:**
**Query docs-management:** "Find skill versioning, updates, and maintenance best practices"

For all distribution details, query docs-management with the patterns above.
