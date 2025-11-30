#!/usr/bin/env python3
"""
Quick Skill Validator - Validates skill structure and content

Performs comprehensive validation of a skill directory including:
- YAML frontmatter syntax and required fields
- Naming conventions and character limits
- File structure and referenced files
- Content quality checks

Usage:
    quick_validate.py <skill_directory>

Examples:
    quick_validate.py .claude/skills/my-skill
    quick_validate.py ~/.claude/skills/api-helper
"""

import sys
import os
import re
from pathlib import Path

# Fix Windows console encoding for emojis
if sys.platform == 'win32':
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')


def print_usage():
    """Print usage instructions and exit."""
    print("Usage: quick_validate.py <skill_directory>")
    print("\nValidates skill structure and content including:")
    print("  - YAML frontmatter syntax and required fields")
    print("  - Naming conventions and character limits")
    print("  - File structure and referenced files")
    print("  - Content quality checks")
    print("\nExamples:")
    print("  quick_validate.py .claude/skills/my-skill")
    print("  quick_validate.py ~/.claude/skills/api-helper")


def validate_yaml_frontmatter(content):
    """
    Validate YAML frontmatter structure and extract fields.

    Args:
        content: Full SKILL.md content

    Returns:
        tuple: (is_valid, frontmatter_dict, error_message)
    """
    # Check for opening delimiter
    if not content.startswith('---'):
        return False, {}, "No YAML frontmatter found (must start with ---)"

    # Extract frontmatter
    match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
    if not match:
        return False, {}, "Invalid frontmatter format (missing closing --- or improper structure)"

    frontmatter = match.group(1)
    frontmatter_dict = {}

    # Extract name field
    name_match = re.search(r'name:\s*(.+)', frontmatter)
    if not name_match:
        return False, {}, "Missing required 'name' field in frontmatter"
    frontmatter_dict['name'] = name_match.group(1).strip()

    # Extract description field
    desc_match = re.search(r'description:\s*(.+)', frontmatter, re.DOTALL)
    if not desc_match:
        return False, {}, "Missing required 'description' field in frontmatter"

    # Handle multi-line descriptions
    desc_text = desc_match.group(1).strip()
    # Stop at next field or end of frontmatter
    next_field_match = re.search(r'\n\w+:', desc_text)
    if next_field_match:
        desc_text = desc_text[:next_field_match.start()].strip()
    frontmatter_dict['description'] = desc_text

    # Extract allowed-tools if present (optional)
    tools_match = re.search(r'allowed-tools:\s*(.+)', frontmatter)
    if tools_match:
        frontmatter_dict['allowed-tools'] = tools_match.group(1).strip()

    return True, frontmatter_dict, ""


def validate_name_field(name, skill_dir_name):
    """
    Validate the name field follows conventions.

    Args:
        name: Name from frontmatter
        skill_dir_name: Directory name of the skill

    Returns:
        tuple: (is_valid, error_message)
    """
    # Check naming convention (hyphen-case: lowercase with hyphens, digits allowed)
    if not re.match(r'^[a-z0-9-]+$', name):
        return False, f"Name '{name}' must use lowercase letters, numbers, and hyphens only"

    # Check for invalid hyphen usage
    if name.startswith('-') or name.endswith('-'):
        return False, f"Name '{name}' cannot start or end with hyphen"

    if '--' in name:
        return False, f"Name '{name}' cannot contain consecutive hyphens"

    # Check max length (64 characters per official docs)
    if len(name) > 64:
        return False, f"Name '{name}' exceeds maximum length of 64 characters ({len(name)} chars)"

    # Check directory name matches
    if name != skill_dir_name:
        return False, f"Name '{name}' does not match directory name '{skill_dir_name}'"

    return True, ""


def validate_description_field(description):
    """
    Validate the description field quality.

    Args:
        description: Description text from frontmatter

    Returns:
        tuple: (is_valid, warning_messages, error_message)
    """
    warnings = []

    # Check max length (1024 characters per official docs)
    if len(description) > 1024:
        return False, warnings, f"Description exceeds maximum length of 1024 characters ({len(description)} chars)"

    # Check for angle brackets (can cause parsing issues)
    if '<' in description or '>' in description:
        return False, warnings, "Description cannot contain angle brackets (< or >)"

    # Check for TODO placeholders
    if 'TODO' in description or '[TODO]' in description:
        warnings.append("Description contains TODO placeholder - should be completed before deployment")

    # Check if description is too short (less than 50 chars is likely incomplete)
    if len(description) < 50:
        warnings.append(f"Description is very short ({len(description)} chars) - consider adding more detail and trigger keywords")

    # Check for trigger words (when, use, working with, etc.)
    trigger_indicators = ['when', 'use', 'working with', 'for', 'should be used']
    has_trigger = any(indicator in description.lower() for indicator in trigger_indicators)
    if not has_trigger:
        warnings.append("Description may be missing trigger scenarios - consider adding 'when to use' guidance")

    return True, warnings, ""


def validate_file_references(skill_path, content):
    """
    Check that files referenced in SKILL.md actually exist.
    Also validates anchor links within files.

    Args:
        skill_path: Path to skill directory
        content: SKILL.md content

    Returns:
        tuple: (warnings_list)
    """
    warnings = []

    # Find markdown links: [text](path)
    # But exclude links inside code blocks (```...```)
    link_pattern = r'\[([^\]]+)\]\(([^)]+)\)'
    
    # Find all code blocks to exclude links within them
    code_block_pattern = r'```[^\n]*\n.*?```'
    code_blocks = list(re.finditer(code_block_pattern, content, re.DOTALL))
    
    for match in re.finditer(link_pattern, content):
        link_text = match.group(1)
        link_path = match.group(2)
        link_start = match.start()

        # Skip if link is inside a code block
        in_code_block = False
        for code_block in code_blocks:
            if code_block.start() <= link_start < code_block.end():
                in_code_block = True
                break
        if in_code_block:
            continue

        # Skip external URLs
        if link_path.startswith('http://') or link_path.startswith('https://'):
            continue

        # Skip pure anchors (links that start with #)
        if link_path.startswith('#'):
            continue

        # Handle links with anchors: file.md#anchor
        file_path = link_path
        anchor = None
        if '#' in link_path:
            parts = link_path.split('#', 1)
            file_path = parts[0]
            anchor = parts[1]

        # Check if file exists
        referenced_file = skill_path / file_path
        if not referenced_file.exists():
            warnings.append(f"Referenced file not found: {file_path}")
            continue

        # If anchor is present, verify it exists in the file
        if anchor:
            try:
                file_content = referenced_file.read_text(encoding='utf-8')
                # Markdown anchors are generated from headings by:
                # 1. Converting to lowercase
                # 2. Replacing spaces with hyphens
                # 3. Removing special characters (keeping only alphanumeric and hyphens)
                
                # Normalize anchor: lowercase, replace underscores with hyphens
                anchor_normalized = anchor.lower().replace('_', '-')
                
                # Extract meaningful words from anchor (split by hyphens)
                anchor_words = [w for w in anchor_normalized.split('-') if w and len(w) > 2]
                
                if not anchor_words:
                    # Anchor has no meaningful words, skip validation
                    continue
                
                # Find all headings in the file
                heading_found = False
                for line in file_content.split('\n'):
                    line_stripped = line.strip()
                    # Check if this is a markdown heading
                    if line_stripped.startswith('#'):
                        # Extract heading text (remove # symbols and whitespace)
                        heading_text = re.sub(r'^#+\s+', '', line_stripped).strip()
                        if not heading_text:
                            continue
                        
                        # Normalize heading text for comparison
                        # Remove special characters, convert to lowercase, replace spaces with hyphens
                        heading_normalized = re.sub(r'[^\w\s-]', '', heading_text.lower())
                        heading_normalized = re.sub(r'\s+', '-', heading_normalized)
                        
                        # Check if normalized heading matches anchor
                        if heading_normalized == anchor_normalized:
                            heading_found = True
                            break
                        
                        # Also check if all anchor words appear in heading (more lenient)
                        heading_lower = heading_text.lower()
                        if all(word in heading_lower for word in anchor_words):
                            heading_found = True
                            break
                
                if not heading_found:
                    warnings.append(f"Anchor not found in file: {link_path} (checked file: {file_path})")
            except Exception as e:
                # If we can't read the file or check anchor, just warn about it
                warnings.append(f"Could not verify anchor in file: {link_path} ({e})")

    return warnings


def validate_skill(skill_path):
    """
    Comprehensive validation of a skill directory.

    Args:
        skill_path: Path to skill directory

    Returns:
        tuple: (is_valid, errors, warnings)
    """
    skill_path = Path(skill_path).resolve()
    errors = []
    warnings = []

    # Check directory exists
    if not skill_path.exists():
        return False, [f"Skill directory not found: {skill_path}"], []

    if not skill_path.is_dir():
        return False, [f"Path is not a directory: {skill_path}"], []

    # Check SKILL.md exists
    skill_md = skill_path / 'SKILL.md'
    if not skill_md.exists():
        return False, ["SKILL.md not found in skill directory"], []

    # Read SKILL.md content
    try:
        content = skill_md.read_text(encoding='utf-8')
    except Exception as e:
        return False, [f"Error reading SKILL.md: {e}"], []

    # Validate YAML frontmatter
    is_valid, frontmatter, error_msg = validate_yaml_frontmatter(content)
    if not is_valid:
        return False, [error_msg], []

    # Validate name field
    name = frontmatter.get('name', '')
    skill_dir_name = skill_path.name
    is_valid, error_msg = validate_name_field(name, skill_dir_name)
    if not is_valid:
        errors.append(error_msg)

    # Validate description field
    description = frontmatter.get('description', '')
    is_valid, desc_warnings, error_msg = validate_description_field(description)
    if not is_valid:
        errors.append(error_msg)
    warnings.extend(desc_warnings)

    # Validate file references
    ref_warnings = validate_file_references(skill_path, content)
    warnings.extend(ref_warnings)

    # Check for very large SKILL.md (>10k words is excessive)
    word_count = len(content.split())
    if word_count > 10000:
        warnings.append(f"SKILL.md is very large ({word_count} words) - consider using references/ for detailed content")

    # Return results
    if errors:
        return False, errors, warnings
    else:
        return True, [], warnings


def main():
    # Check for help flag first
    if len(sys.argv) >= 2 and sys.argv[1] in ['--help', '-h']:
        print_usage()
        sys.exit(0)

    if len(sys.argv) != 2:
        print_usage()
        sys.exit(1)

    skill_path = sys.argv[1]

    print(f"🔍 Validating skill: {skill_path}")
    print()

    is_valid, errors, warnings = validate_skill(skill_path)

    # Print errors
    if errors:
        print("❌ Validation failed with errors:")
        for error in errors:
            print(f"   • {error}")
        print()

    # Print warnings
    if warnings:
        print("⚠️  Warnings:")
        for warning in warnings:
            print(f"   • {warning}")
        print()

    # Print final result
    if is_valid:
        if warnings:
            print("✅ Skill is valid (with warnings above)")
        else:
            print("✅ Skill is valid!")
        sys.exit(0)
    else:
        print("❌ Skill validation failed. Please fix the errors above.")
        sys.exit(1)


if __name__ == "__main__":
    main()
