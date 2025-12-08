#!/usr/bin/env python3
"""
frontmatter_parser.py - YAML frontmatter extraction for capability indexing

Extracts YAML frontmatter from SKILL.md, agent .md, and command .md files.
Lightweight parser focused on extraction, not validation.

Usage:
    from frontmatter_parser import extract_frontmatter
    metadata = extract_frontmatter(file_path)
"""

import sys
import io
from pathlib import Path
from typing import Optional


# Input bounds for security
MAX_CONTENT_SIZE = 100_000  # 100KB max file content
MAX_LINES = 1000  # Maximum lines to process


# Set UTF-8 encoding for stdout/stderr on all platforms (Windows fix)
if sys.stdout.encoding != 'utf-8':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
if sys.stderr.encoding != 'utf-8':
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')


def extract_frontmatter(file_path: Path) -> Optional[dict]:
    """
    Extract YAML frontmatter from a markdown file.

    Args:
        file_path: Path to the markdown file

    Returns:
        Dictionary of frontmatter key-value pairs, or None if no frontmatter found.
        Returns empty dict if frontmatter exists but is empty.
    """
    try:
        content = file_path.read_text(encoding='utf-8')
    except Exception:
        return None

    return extract_frontmatter_from_content(content)


def extract_frontmatter_from_content(content: str) -> Optional[dict]:
    """
    Extract YAML frontmatter from markdown content string.

    Args:
        content: Markdown file content

    Returns:
        Dictionary of frontmatter key-value pairs, or None if no frontmatter found.
        Returns None if content exceeds MAX_CONTENT_SIZE.
    """
    # Security: Reject overly large content
    if len(content) > MAX_CONTENT_SIZE:
        return None

    # Security: Limit lines processed
    lines = content.split('\n')[:MAX_LINES]

    # Check first line is opening delimiter
    if not lines or lines[0].strip() != '---':
        return None

    # Find closing delimiter
    closing_line = None
    for i, line in enumerate(lines[1:], start=1):
        if line.strip() == '---':
            closing_line = i
            break

    if closing_line is None:
        return None

    # Extract YAML content between delimiters
    yaml_lines = lines[1:closing_line]

    # Parse YAML (simple key: value parser)
    yaml_dict = {}
    current_key = None
    multiline_value = []
    in_multiline = False

    for line in yaml_lines:
        # Skip empty lines
        if not line.strip():
            if in_multiline:
                multiline_value.append('')
            continue

        # Check for key: value
        if ':' in line and not line.startswith(' ') and not line.startswith('\t'):
            # Save previous multiline if any
            if in_multiline and current_key:
                yaml_dict[current_key] = '\n'.join(multiline_value).strip()
                multiline_value = []
                in_multiline = False

            # Parse new key: value
            colon_pos = line.index(':')
            key = line[:colon_pos].strip()
            value = line[colon_pos + 1:].strip()

            # Check for multiline indicator
            if value in ('|', '>'):
                current_key = key
                in_multiline = True
                multiline_value = []
            else:
                yaml_dict[key] = value
                current_key = key
        elif in_multiline:
            # Continuation of multiline value
            multiline_value.append(line)

    # Save final multiline if any
    if in_multiline and current_key:
        yaml_dict[current_key] = '\n'.join(multiline_value).strip()

    return yaml_dict


def extract_keywords_from_description(description: str, max_keywords: int = 8) -> list:
    """
    Extract key terms from description for keyword matching.

    Uses simple heuristics: looks for domain terms, tool names, action verbs.
    No NLP dependencies required.

    Args:
        description: The description text
        max_keywords: Maximum number of keywords to extract

    Returns:
        List of extracted keywords
    """
    if not description:
        return []

    # Common stopwords to ignore
    stopwords = {
        'a', 'an', 'the', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
        'of', 'with', 'by', 'from', 'as', 'is', 'was', 'are', 'were', 'been',
        'be', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would',
        'could', 'should', 'may', 'might', 'must', 'shall', 'can', 'this',
        'that', 'these', 'those', 'it', 'its', 'use', 'when', 'where', 'how',
        'what', 'which', 'who', 'whom', 'whose', 'why', 'all', 'any', 'both',
        'each', 'few', 'more', 'most', 'other', 'some', 'such', 'no', 'nor',
        'not', 'only', 'own', 'same', 'so', 'than', 'too', 'very', 'just',
        'about', 'into', 'through', 'during', 'before', 'after', 'above',
        'below', 'between', 'under', 'again', 'further', 'then', 'once'
    }

    # Domain terms that should be preserved if found
    domain_terms = {
        'claude', 'hooks', 'mcp', 'sdk', 'api', 'git', 'github', 'yaml',
        'json', 'markdown', 'python', 'bash', 'typescript', 'gemini',
        'documentation', 'plugin', 'skill', 'agent', 'command', 'config',
        'settings', 'memory', 'session', 'security', 'permissions',
        'sandbox', 'output', 'status', 'enterprise', 'auth', 'oauth'
    }

    # Extract words, normalize
    import re
    words = re.findall(r'\b[a-zA-Z][a-zA-Z0-9-]*\b', description.lower())

    # Score words
    scored = []
    seen = set()

    for word in words:
        if word in seen or word in stopwords or len(word) < 3:
            continue
        seen.add(word)

        score = 0
        # Domain terms get high score
        if word in domain_terms:
            score += 10
        # Longer words tend to be more meaningful
        if len(word) >= 6:
            score += 2
        # Words with hyphens are often technical terms
        if '-' in word:
            score += 3
        # Capitalized words in original (proper nouns, acronyms)
        if any(w.isupper() or w[0].isupper() for w in re.findall(r'\b' + word + r'\b', description, re.IGNORECASE)):
            score += 1

        if score > 0:
            scored.append((word, score))

    # Sort by score descending
    scored.sort(key=lambda x: -x[1])

    # Return top keywords
    return [word for word, _ in scored[:max_keywords]]


def truncate_description(description: str, max_chars: int = 80) -> str:
    """
    Truncate description to first sentence or max_chars.

    Args:
        description: Full description text
        max_chars: Maximum characters

    Returns:
        Truncated description
    """
    if not description:
        return ''

    # Remove newlines
    description = ' '.join(description.split())

    # Find first sentence end
    for end_marker in ['. ', '! ', '? ']:
        pos = description.find(end_marker)
        if 0 < pos < max_chars:
            return description[:pos + 1]

    # No sentence end found, truncate at word boundary
    if len(description) <= max_chars:
        return description

    truncated = description[:max_chars]
    last_space = truncated.rfind(' ')
    if last_space > max_chars // 2:
        return truncated[:last_space] + '...'
    return truncated + '...'


if __name__ == '__main__':
    # Simple test
    if len(sys.argv) > 1:
        path = Path(sys.argv[1])
        result = extract_frontmatter(path)
        if result:
            print(f"Extracted from {path}:")
            for k, v in result.items():
                print(f"  {k}: {v[:50]}..." if len(str(v)) > 50 else f"  {k}: {v}")
        else:
            print(f"No frontmatter found in {path}")
