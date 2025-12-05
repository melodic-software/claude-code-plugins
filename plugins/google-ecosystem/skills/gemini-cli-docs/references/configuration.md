# Configuration Reference

## Table of Contents

- [Configuration Files](#configuration-files)
- [defaults.yaml](#defaultsyaml)
- [filtering.yaml](#filteringyaml)
- [tag_detection.yaml](#tag_detectionyaml)
- [Environment Variables](#environment-variables)
- [Runtime Configuration](#runtime-configuration)

---

## Configuration Files

The gemini-cli-docs skill uses three configuration files in the `config/` directory:

| File | Purpose |
|------|---------|
| `defaults.yaml` | Core settings, paths, scraping options |
| `filtering.yaml` | Content filtering rules |
| `tag_detection.yaml` | Tag detection patterns |

---

## defaults.yaml

### Core Settings

```yaml
# Skill identification
skill_name: gemini-cli-docs
skill_version: "1.0.0"

# Base paths (relative to skill root)
paths:
  canonical: canonical
  scripts: scripts
  config: config
  cache: cache
  logs: logs
```

### Scraping Settings

```yaml
scraping:
  # Rate limiting (seconds between requests)
  delay_between_requests: 1.5

  # Request timeout (seconds)
  timeout: 30

  # User agent for requests
  user_agent: "GeminiDocsSkill/1.0"

  # Skip existing files on re-scrape
  skip_existing: false

  # Maximum retries per URL
  max_retries: 3
```

### Index Settings

```yaml
index:
  # Primary index file
  primary: index.yaml

  # JSON mirror (for programmatic access)
  json_mirror: index.json

  # Enable keyword extraction
  extract_keywords: true

  # Maximum keywords per document
  max_keywords: 20
```

### Search Settings

```yaml
search:
  # Default result limit
  default_limit: 25

  # Minimum score threshold (null = no threshold)
  min_score_default: null

  # Domain weight boosts
  domain_weights:
    geminicli.com: 10.0
```

### Cache Settings

```yaml
cache:
  # Enable inverted index caching
  inverted_index: true

  # Cache TTL (seconds, 0 = no expiry)
  ttl: 0
```

---

## filtering.yaml

### Content Filtering Rules

```yaml
# Sections to remove from scraped content
remove_sections:
  - "Table of Contents"
  - "On this page"
  - "Edit this page"

# HTML elements to strip
strip_elements:
  - "nav"
  - "footer"
  - "aside.sidebar"

# Patterns to filter from content
filter_patterns:
  - "^\\s*$"  # Empty lines
  - "^---$"   # Horizontal rules (standalone)
```

### Frontmatter Handling

```yaml
frontmatter:
  # Preserve existing frontmatter
  preserve: true

  # Required frontmatter fields
  required:
    - title
    - url

  # Auto-generated fields
  auto_generate:
    - doc_id
    - domain
    - last_fetched
```

---

## tag_detection.yaml

### Tag Detection Patterns

```yaml
# URL-based tag detection
url_patterns:
  - pattern: "/docs/installation"
    tags: ["getting-started", "installation"]

  - pattern: "/docs/commands"
    tags: ["cli", "commands"]

  - pattern: "/docs/tools"
    tags: ["tools", "functions"]

  - pattern: "/docs/mcp"
    tags: ["mcp", "integration"]

  - pattern: "/docs/checkpointing"
    tags: ["session-management", "checkpointing"]

# Content-based tag detection
content_patterns:
  - pattern: "gemini\\s+(pro|flash|ultra)"
    tags: ["models"]

  - pattern: "sandbox"
    tags: ["security", "isolation"]
```

### Category Mapping

```yaml
categories:
  docs:
    description: "Official documentation"
    priority: 1

  guides:
    description: "How-to guides"
    priority: 2

  reference:
    description: "API reference"
    priority: 3
```

---

## Environment Variables

### Development Mode

```bash
# Use local plugin code instead of installed plugin
export GEMINI_DOCS_DEV_ROOT=/path/to/claude-code-plugins
```

### Python Configuration

```bash
# Force UTF-8 encoding (usually auto-detected)
export PYTHONIOENCODING=utf-8

# Python path for imports
export PYTHONPATH=/path/to/skill/scripts:$PYTHONPATH
```

### Platform-Specific

**Git Bash (Windows):**

```bash
# Prevent path conversion issues
export MSYS_NO_PATHCONV=1
```

**PowerShell:**

```powershell
# Set dev mode
$env:GEMINI_DOCS_DEV_ROOT = "D:\repos\gh\melodic\claude-code-plugins"
```

---

## Runtime Configuration

### Script Arguments

Most scripts accept runtime configuration via command-line arguments:

**Scraping:**

```bash
python scripts/core/scrape_docs.py \
    --llms-txt https://geminicli.com/llms.txt \
    --filter "/docs/" \
    --skip-existing \
    --delay 2.0
```

**Index Management:**

```bash
python scripts/management/manage_index.py refresh \
    --extract-keywords \
    --max-keywords 25
```

**Drift Detection:**

```bash
python scripts/maintenance/detect_changes.py \
    --check-404s \
    --check-hashes \
    --max-workers 10
```

### Programmatic Configuration

Via the Public API:

```python
from gemini_docs_api import GeminiDocsAPI

api = GeminiDocsAPI()

# Search with custom limit
results = api.find_document("checkpointing", limit=50)

# Drift detection with custom workers
drift = api.detect_drift(check_404s=True, max_workers=20)

# Cleanup with dry run
result = api.cleanup_drift(clean_404s=True, dry_run=True)
```

---

## Configuration Precedence

When multiple configuration sources exist:

1. **Command-line arguments** (highest priority)
2. **Environment variables**
3. **Config files** (defaults.yaml, etc.)
4. **Hardcoded defaults** (lowest priority)

---

## Validating Configuration

### Check Configuration Files

```bash
# Validate YAML syntax
python -c "import yaml; yaml.safe_load(open('config/defaults.yaml'))"
python -c "import yaml; yaml.safe_load(open('config/filtering.yaml'))"
python -c "import yaml; yaml.safe_load(open('config/tag_detection.yaml'))"
```

### Check Dependencies

```bash
python scripts/setup/check_dependencies.py
```

### Validate Tag Configuration

```bash
python scripts/validation/audit_tag_config.py
```
