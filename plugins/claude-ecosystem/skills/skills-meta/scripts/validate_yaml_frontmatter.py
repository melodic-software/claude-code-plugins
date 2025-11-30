#!/usr/bin/env python3
"""
YAML Frontmatter Validator for Claude Code Skills

Validates SKILL.md YAML frontmatter against official Claude Code specification.
Provides deterministic validation with clear error messages.

Official Specification:
- Required fields: name, description
- Optional fields: allowed-tools
- No other fields are allowed

Usage:
    python validate_yaml_frontmatter.py <skill-directory>
    python validate_yaml_frontmatter.py .claude/skills/python/

Exit Codes:
    0 - Validation passed
    1 - Validation failed
    2 - Error reading file or parsing YAML
"""

import sys
import io
from pathlib import Path
import re


# Set UTF-8 encoding for stdout/stderr on all platforms (Windows fix)
if sys.stdout.encoding != 'utf-8':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
if sys.stderr.encoding != 'utf-8':
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')


# OFFICIAL FIELD WHITELIST (Claude Code Specification)
VALID_FIELDS = {"name", "description", "allowed-tools"}
REQUIRED_FIELDS = {"name", "description"}
OPTIONAL_FIELDS = {"allowed-tools"}

# Common invalid fields (for helpful error messages)
COMMON_INVALID_FIELDS = {
    "version": "Version information belongs in the skill body (Version History section), not YAML frontmatter",
    "location": "Skill location is determined by file path, not metadata",
    "author": "Author information belongs in the skill body, not YAML frontmatter",
    "tags": "Use description keywords instead of tags",
    "category": "Use description keywords instead of categories",
    "dependencies": "Document dependencies in the skill body, not YAML frontmatter",
}


class ValidationError(Exception):
    """Validation failed"""
    pass


def extract_yaml_frontmatter(content: str) -> tuple[dict[str, str], int, int]:
    """
    Extract YAML frontmatter from SKILL.md content.

    Returns:
        (yaml_dict, start_line, end_line)

    Raises:
        ValidationError if frontmatter is invalid
    """
    lines = content.split('\n')

    # Check first line is opening delimiter
    if not lines or lines[0].strip() != '---':
        raise ValidationError("YAML frontmatter must start with '---' on line 1")

    # Find closing delimiter
    closing_line = None
    for i, line in enumerate(lines[1:], start=1):
        if line.strip() == '---':
            closing_line = i
            break

    if closing_line is None:
        raise ValidationError("YAML frontmatter missing closing '---'")

    # Extract YAML content
    yaml_lines = lines[1:closing_line]

    # Parse YAML manually (simple key: value parser)
    yaml_dict = {}
    current_key = None
    multiline_value = []
    in_multiline = False

    for line_num, line in enumerate(yaml_lines, start=2):
        # Skip empty lines
        if not line.strip():
            continue

        # Check for key: value
        if ':' in line and not line.startswith(' '):
            # Save previous multiline if any
            if in_multiline and current_key:
                yaml_dict[current_key] = '\n'.join(multiline_value).strip()
                multiline_value = []
                in_multiline = False

            # Parse new key: value
            key, value = line.split(':', 1)
            key = key.strip()
            value = value.strip()

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
        else:
            raise ValidationError(f"Invalid YAML syntax on line {line_num}: {line}")

    # Save final multiline if any
    if in_multiline and current_key:
        yaml_dict[current_key] = '\n'.join(multiline_value).strip()

    return yaml_dict, 1, closing_line


def validate_field_whitelist(yaml_dict: dict[str, str]) -> list[str]:
    """
    Validate that only whitelisted fields are present.

    Returns:
        List of error messages (empty if valid)
    """
    errors = []

    for field in yaml_dict.keys():
        if field not in VALID_FIELDS:
            error_msg = f"Invalid YAML field: '{field}'"

            # Add helpful context for common mistakes
            if field in COMMON_INVALID_FIELDS:
                error_msg += f"\n  → {COMMON_INVALID_FIELDS[field]}"
            else:
                error_msg += f"\n  → Only these fields are allowed: {', '.join(sorted(VALID_FIELDS))}"

            errors.append(error_msg)

    return errors


def validate_required_fields(yaml_dict: dict[str, str]) -> list[str]:
    """
    Validate that all required fields are present.

    Returns:
        List of error messages (empty if valid)
    """
    errors = []

    for field in REQUIRED_FIELDS:
        if field not in yaml_dict:
            errors.append(f"Missing required field: '{field}'")

    return errors


def validate_name_field(value: str) -> list[str]:
    """
    Validate 'name' field format.

    Requirements:
    - Lowercase letters, numbers, hyphens only (a-z, 0-9, -)
    - Maximum 64 characters
    - No underscores, no spaces, no special characters
    - Cannot contain reserved words: "anthropic", "claude"
    - Cannot contain XML tags

    Returns:
        List of error messages (empty if valid)
    """
    errors = []

    if not value:
        errors.append("Field 'name' cannot be empty")
        return errors

    # Check length
    if len(value) > 64:
        errors.append(f"Field 'name' exceeds maximum length (64 chars): {len(value)} chars")

    # Check format (lowercase, numbers, hyphens only)
    if not re.match(r'^[a-z0-9-]+$', value):
        errors.append(f"Field 'name' contains invalid characters: '{value}'")
        errors.append("  → Only lowercase letters (a-z), numbers (0-9), and hyphens (-) are allowed")

        # Provide specific feedback
        if any(c.isupper() for c in value):
            errors.append("  → Contains uppercase letters (must be lowercase)")
        if '_' in value:
            errors.append("  → Contains underscores (use hyphens instead)")
        if ' ' in value:
            errors.append("  → Contains spaces (use hyphens instead)")

    # Check for reserved words (official best practice - "Avoid" per docs)
    # This is a WARNING, not an error, because:
    # 1. Official docs say "Avoid" not "Must not use"
    # 2. Project-level skills managing Claude docs may legitimately use these
    # 3. The concern is impersonation in distributed skills, not internal tools
    reserved_words = ['anthropic', 'claude']
    for word in reserved_words:
        if word in value.lower():
            errors.append(
                f"WARNING: Field 'name' contains reserved word: '{word}'\n"
                f"  → Official docs recommend avoiding '{word}' in skill names\n"
                f"  → Acceptable for project-level skills managing Claude/Anthropic content"
            )

    # Check for XML tags (official requirement)
    if '<' in value or '>' in value:
        errors.append("Field 'name' contains XML tag characters (< or >)")
        errors.append("  → XML tags are not allowed in skill names (official requirement)")

    return errors


def validate_description_field(value: str) -> list[str]:
    """
    Validate 'description' field format.

    Requirements:
    - Maximum 1024 characters
    - Should include what the skill does AND when to use it
    - Should be written in third person
    - Cannot contain XML tags

    Returns:
        List of error messages (empty if valid)
    """
    errors = []

    if not value:
        errors.append("Field 'description' cannot be empty")
        return errors

    # Check length
    if len(value) > 1024:
        errors.append(f"Field 'description' exceeds maximum length (1024 chars): {len(value)} chars")

    # Check for XML tags (official requirement)
    if '<' in value or '>' in value:
        errors.append("Field 'description' contains XML tag characters (< or >)")
        errors.append("  → XML tags are not allowed in descriptions (official requirement)")

    # Warning: Check for quality (non-fatal)
    if len(value) < 50:
        errors.append(f"WARNING: Field 'description' is very short ({len(value)} chars)")
        errors.append("  → Consider adding trigger keywords (file types, domains, tasks, tools)")

    # Warning: Check for first/second person (should be third person)
    first_person_indicators = ['I ', 'my ', 'me ', 'we ', 'our ']
    second_person_indicators = ['you ', 'your ']

    if any(indicator in value for indicator in first_person_indicators):
        errors.append("WARNING: Field 'description' appears to use first person")
        errors.append("  → Descriptions should be written in third person (e.g., 'Analyzes...' not 'I analyze...')")

    if any(indicator in value for indicator in second_person_indicators):
        errors.append("WARNING: Field 'description' appears to use second person")
        errors.append("  → Descriptions should be written in third person (e.g., 'Use when...' not 'You can...')")

    return errors


def validate_allowed_tools_field(value: str) -> list[str]:
    """
    Validate 'allowed-tools' field format.

    Requirements:
    - Comma-separated list of tool names
    - Tool names are case-sensitive (e.g., 'Read' not 'read')

    Returns:
        List of error messages (empty if valid)
    """
    errors = []

    if not value:
        errors.append("WARNING: Field 'allowed-tools' is empty (consider removing if unused)")
        return errors

    # VALID_TOOLS - Claude Code tool whitelist
    # Source: Official Claude Code documentation
    # Verification: Run `check_yaml_spec_currency.py` quarterly
    # Last verified: 2025-11-25
    # Query official-docs: "Find allowed-tools configuration for skills"
    # Note: Tool names are case-sensitive (PascalCase)
    VALID_TOOLS = {
        'Read', 'Write', 'Edit',
        'Grep', 'Glob',
        'Bash', 'BashOutput', 'KillShell',
        'WebFetch', 'WebSearch',
        'Task', 'Skill', 'SlashCommand',
        'NotebookEdit',
        'TodoWrite',
        'AskUserQuestion',
        'EnterPlanMode', 'ExitPlanMode',
    }

    tools = [tool.strip() for tool in value.split(',')]

    for tool in tools:
        if tool not in VALID_TOOLS:
            # Check if it's a case issue
            if tool.lower() in [t.lower() for t in VALID_TOOLS]:
                errors.append(f"WARNING: Tool name '{tool}' has incorrect case")
                correct = [t for t in VALID_TOOLS if t.lower() == tool.lower()][0]
                errors.append(f"  → Should be '{correct}' (tool names are case-sensitive)")
            else:
                errors.append(f"WARNING: Unknown tool name '{tool}'")
                errors.append(f"  → Common tools: {', '.join(sorted(VALID_TOOLS))}")

    return errors


def validate_field_formats(yaml_dict: dict[str, str]) -> list[str]:
    """
    Validate individual field formats.

    Returns:
        List of error messages (empty if valid)
    """
    errors = []

    # Validate 'name' field
    if 'name' in yaml_dict:
        errors.extend(validate_name_field(yaml_dict['name']))

    # Validate 'description' field
    if 'description' in yaml_dict:
        errors.extend(validate_description_field(yaml_dict['description']))

    # Validate 'allowed-tools' field
    if 'allowed-tools' in yaml_dict:
        errors.extend(validate_allowed_tools_field(yaml_dict['allowed-tools']))

    return errors


def validate_skill_directory_match(skill_dir: Path, yaml_dict: dict[str, str]) -> list[str]:
    """
    Validate that 'name' field matches skill directory name.

    Returns:
        List of error messages (empty if valid)
    """
    errors = []

    if 'name' not in yaml_dict:
        return errors  # Already flagged by required fields check

    skill_name = yaml_dict['name']
    dir_name = skill_dir.name

    if skill_name != dir_name:
        errors.append(f"Field 'name' ('{skill_name}') does not match directory name ('{dir_name}')")
        errors.append(f"  → Rename directory to '{skill_name}/' OR update name field to '{dir_name}'")

    return errors


def validate_skill(skill_dir: Path) -> tuple[bool, list[str], list[str]]:
    """
    Validate SKILL.md YAML frontmatter in a skill directory.

    Args:
        skill_dir: Path to skill directory

    Returns:
        (success, errors, warnings)
        - success: True if validation passed
        - errors: List of error messages (fatal issues)
        - warnings: List of warning messages (non-fatal issues)
    """
    skill_md = skill_dir / 'SKILL.md'

    # Check SKILL.md exists
    if not skill_md.exists():
        return False, [f"SKILL.md not found in {skill_dir}"], []

    # Read SKILL.md
    try:
        content = skill_md.read_text(encoding='utf-8')
    except Exception as e:
        return False, [f"Error reading SKILL.md: {e}"], []

    # Extract YAML frontmatter
    try:
        yaml_dict, start_line, end_line = extract_yaml_frontmatter(content)
    except ValidationError as e:
        return False, [str(e)], []

    # Collect all errors and warnings
    errors = []
    warnings = []

    # Validation Phase 1: Field Whitelist (CRITICAL - fail-fast)
    whitelist_errors = validate_field_whitelist(yaml_dict)
    if whitelist_errors:
        errors.extend(whitelist_errors)
        # Don't continue if whitelist fails - other validations may be confusing
        return False, errors, warnings

    # Validation Phase 2: Required Fields
    errors.extend(validate_required_fields(yaml_dict))

    # Validation Phase 3: Field Formats
    format_errors = validate_field_formats(yaml_dict)
    # Separate errors from warnings
    for error in format_errors:
        if error.startswith('WARNING:'):
            warnings.append(error)
        else:
            errors.append(error)

    # Validation Phase 4: Directory Match
    errors.extend(validate_skill_directory_match(skill_dir, yaml_dict))

    # Success if no errors
    success = len(errors) == 0

    return success, errors, warnings


def print_validation_results(skill_dir: Path, success: bool, errors: list[str], warnings: list[str]):
    """Print validation results in a user-friendly format."""
    print(f"\n{'='*70}")
    print(f"Validating: {skill_dir}")
    print(f"{'='*70}\n")

    if success and not warnings:
        print("✅ PASS - YAML frontmatter is valid\n")
        return

    if success and warnings:
        print("✅ PASS (with warnings) - YAML frontmatter is valid\n")
    else:
        print("❌ FAIL - YAML frontmatter validation failed\n")

    # Print errors
    if errors:
        print("ERRORS (must fix):")
        print("-" * 70)
        for error in errors:
            # Indent continuation lines
            lines = error.split('\n')
            print(f"  • {lines[0]}")
            for line in lines[1:]:
                print(f"    {line}")
        print()

    # Print warnings
    if warnings:
        print("WARNINGS (should fix):")
        print("-" * 70)
        for warning in warnings:
            # Indent continuation lines
            lines = warning.split('\n')
            print(f"  ⚠️ {lines[0]}")
            for line in lines[1:]:
                print(f"    {line}")
        print()


def main():
    """Main entry point."""
    if len(sys.argv) != 2:
        print("Usage: python validate_yaml_frontmatter.py <skill-directory>")
        print("\nExample:")
        print("  python validate_yaml_frontmatter.py .claude/skills/python/")
        sys.exit(2)

    skill_dir = Path(sys.argv[1])

    # Validate skill directory exists
    if not skill_dir.exists():
        print(f"❌ Error: Skill directory not found: {skill_dir}")
        sys.exit(2)

    if not skill_dir.is_dir():
        print(f"❌ Error: Not a directory: {skill_dir}")
        sys.exit(2)

    # Run validation
    try:
        success, errors, warnings = validate_skill(skill_dir)
    except Exception as e:
        print(f"❌ Unexpected error during validation: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(2)

    # Print results
    print_validation_results(skill_dir, success, errors, warnings)

    # Exit with appropriate code
    if success:
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == '__main__':
    main()
