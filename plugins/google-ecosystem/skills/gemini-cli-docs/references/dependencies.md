# Dependencies

## Table of Contents

- [Python Version](#python-version)
- [Required Dependencies](#required-dependencies)
- [Optional Dependencies](#optional-dependencies)
- [Installation](#installation)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)

---

## Python Version

| Version | Status | Notes |
|---------|--------|-------|
| Python 3.13 | **Recommended** | Required for spaCy operations |
| Python 3.12 | Supported | Most features work |
| Python 3.11 | Minimum | Basic functionality only |
| Python < 3.11 | Not supported | Will not work |

**Why Python 3.13?**

- spaCy 3.7+ requires Python 3.9+ but works best with 3.13
- Type hints use modern syntax (e.g., `dict[str, Any]` instead of `Dict[str, Any]`)
- Performance improvements in recent Python versions

---

## Required Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| PyYAML | >= 6.0 | YAML parsing for index.yaml |
| requests | >= 2.28 | HTTP requests for scraping |
| beautifulsoup4 | >= 4.11 | HTML parsing |
| markdownify | >= 0.11 | HTML to Markdown conversion |
| filelock | >= 3.0 | File locking for concurrent access |

### Installation

```bash
pip install PyYAML>=6.0 requests>=2.28 beautifulsoup4>=4.11 markdownify>=0.11 filelock>=3.0
```

Or with requirements file:

```bash
pip install -r plugins/google-ecosystem/skills/gemini-cli-docs/requirements.txt
```

---

## Optional Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| spacy | >= 3.7 | Keyword extraction (NLP) |
| en_core_web_sm | N/A | spaCy English language model |

### spaCy Installation

```bash
# Install spaCy
pip install spacy>=3.7

# Download English model
python -m spacy download en_core_web_sm
```

**Note:** If spaCy is not installed, keyword extraction will be skipped. Documents will still be indexed but without auto-generated keywords.

---

## Installation

### Basic Installation (Required Only)

```bash
pip install PyYAML requests beautifulsoup4 markdownify filelock
```

### Full Installation (With spaCy)

```bash
pip install PyYAML requests beautifulsoup4 markdownify filelock spacy
python -m spacy download en_core_web_sm
```

### Using pip with Python 3.13

If you have multiple Python versions:

```bash
# Windows
py -3.13 -m pip install PyYAML requests beautifulsoup4 markdownify filelock spacy
py -3.13 -m spacy download en_core_web_sm

# Linux/macOS
python3.13 -m pip install PyYAML requests beautifulsoup4 markdownify filelock spacy
python3.13 -m spacy download en_core_web_sm
```

---

## Verification

### Check All Dependencies

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/setup/check_dependencies.py
```

### Manual Verification

```python
# Check required packages
import yaml
import requests
from bs4 import BeautifulSoup
import markdownify
import filelock

print("Required dependencies: OK")

# Check optional packages
try:
    import spacy
    nlp = spacy.load("en_core_web_sm")
    print("spaCy: OK")
except ImportError:
    print("spaCy: Not installed (optional)")
except OSError:
    print("spaCy: Installed but model missing")
```

### Version Check

```bash
pip show PyYAML requests beautifulsoup4 markdownify filelock spacy
```

---

## Troubleshooting

### PyYAML Import Error

**Symptom:** `ModuleNotFoundError: No module named 'yaml'`

**Solution:**

```bash
pip install PyYAML
```

### requests SSL Error

**Symptom:** SSL certificate verification failed

**Solutions:**

1. Update certifi:

   ```bash
   pip install --upgrade certifi
   ```

2. If behind corporate proxy, configure proxy settings

### BeautifulSoup Parser Warning

**Symptom:** Warning about parser not specified

**Solution:** Scripts explicitly use `html.parser` - this warning can be ignored.

### spaCy Model Not Found

**Symptom:** `OSError: [E050] Can't find model 'en_core_web_sm'`

**Solution:**

```bash
python -m spacy download en_core_web_sm
```

### filelock Permission Error

**Symptom:** Cannot acquire file lock

**Solutions:**

1. Check file permissions on cache/ directory
2. Ensure no other process is holding the lock
3. Delete stale .lock files if process crashed

### Python Version Mismatch

**Symptom:** Syntax errors or import failures

**Solution:** Ensure you're using Python 3.11+:

```bash
python --version
# If wrong version:
py -3.13 scripts/core/scrape_docs.py ...
```

---

## Platform-Specific Notes

### Windows

- Use `py -3.13` launcher to select Python version
- PowerShell recommended over CMD for Unicode support
- Git Bash may need `MSYS_NO_PATHCONV=1` for path arguments

### macOS

- Use `python3.13` or pyenv to manage versions
- Xcode command line tools may be required for some packages

### Linux

- Use system package manager or pyenv for Python 3.13
- May need `python3.13-dev` package for compiling extensions
