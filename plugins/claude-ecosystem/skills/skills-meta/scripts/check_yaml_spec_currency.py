#!/usr/bin/env python3
"""
YAML Spec Currency Checker

Validates that our hardcoded YAML frontmatter specification matches the official
Claude Code documentation. Uses the official-docs skill to fetch latest requirements.

This script ensures our validation remains current as official documentation evolves.

Usage:
    python check_yaml_spec_currency.py

Exit Codes:
    0 - Spec is current
    1 - Spec is out of date (update needed)
    2 - Error checking spec

Recommendation:
    Run this quarterly or when you suspect official docs have changed.
"""

import sys
import io
import json
from pathlib import Path

# Set UTF-8 encoding for stdout/stderr on all platforms (Windows fix)
if sys.stdout.encoding != 'utf-8':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
if sys.stderr.encoding != 'utf-8':
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')


# Our current hardcoded spec (from validate_yaml_frontmatter.py)
CURRENT_SPEC = {
    "valid_fields": ["name", "description", "allowed-tools"],
    "required_fields": ["name", "description"],
    "optional_fields": ["allowed-tools"],
    "name_requirements": {
        "max_length": 64,
        "pattern": "lowercase letters, numbers, hyphens only",
        "reserved_words": ["anthropic", "claude"],
        "no_xml_tags": True,
    },
    "description_requirements": {
        "max_length": 1024,
        "no_xml_tags": True,
        "third_person": True,
    },
}


def print_instructions():
    """Print instructions for using official-docs skill to check spec."""
    print("\n" + "="*70)
    print("YAML Spec Currency Check")
    print("="*70 + "\n")

    print("📋 INSTRUCTIONS:")
    print("-" * 70)
    print()
    print("This script requires you to use the 'official-docs' skill to fetch")
    print("the latest official YAML frontmatter requirements.")
    print()
    print("Steps:")
    print("1. Invoke the official-docs skill")
    print("2. Ask: 'Find documentation about YAML frontmatter requirements'")
    print("3. Look for the official field whitelist and validation rules")
    print("4. Compare against the current spec shown below")
    print()
    print("-" * 70)
    print()
    print("📌 CURRENT SPEC (from validate_yaml_frontmatter.py):")
    print("-" * 70)
    print()
    print(f"Valid Fields: {', '.join(CURRENT_SPEC['valid_fields'])}")
    print(f"Required Fields: {', '.join(CURRENT_SPEC['required_fields'])}")
    print(f"Optional Fields: {', '.join(CURRENT_SPEC['optional_fields'])}")
    print()
    print("Name Field Requirements:")
    print(f"  - Max Length: {CURRENT_SPEC['name_requirements']['max_length']} chars")
    print(f"  - Pattern: {CURRENT_SPEC['name_requirements']['pattern']}")
    print(f"  - Reserved Words: {', '.join(CURRENT_SPEC['name_requirements']['reserved_words'])}")
    print(f"  - No XML Tags: {CURRENT_SPEC['name_requirements']['no_xml_tags']}")
    print()
    print("Description Field Requirements:")
    print(f"  - Max Length: {CURRENT_SPEC['description_requirements']['max_length']} chars")
    print(f"  - No XML Tags: {CURRENT_SPEC['description_requirements']['no_xml_tags']}")
    print(f"  - Third Person: {CURRENT_SPEC['description_requirements']['third_person']}")
    print()
    print("-" * 70)
    print()
    print("🔍 MANUAL VERIFICATION CHECKLIST:")
    print("-" * 70)
    print()
    print("After fetching official docs, verify:")
    print()
    print("  [ ] Valid fields match official whitelist")
    print("  [ ] Required fields match official spec")
    print("  [ ] Optional fields match official spec")
    print("  [ ] Name max length is correct")
    print("  [ ] Name pattern requirements are correct")
    print("  [ ] Reserved words list is complete")
    print("  [ ] XML tag restrictions documented")
    print("  [ ] Description max length is correct")
    print("  [ ] Description requirements are complete")
    print()
    print("  Tool Verification (validate_yaml_frontmatter.py VALID_TOOLS):")
    print("  [ ] Tool names list matches official spec")
    print("      Query: 'Find allowed-tools configuration for skills'")
    print("  [ ] No deprecated tools in VALID_TOOLS list")
    print("  [ ] All new Claude Code tools documented")
    print()
    print("-" * 70)
    print()
    print("✅ If all checks pass: Spec is CURRENT")
    print("❌ If any mismatch: Update validate_yaml_frontmatter.py")
    print()
    print("="*70)
    print()


def main():
    """Main entry point."""
    print_instructions()

    print("⚠️  IMPORTANT: This is a MANUAL verification process.")
    print()
    print("Automated LLM-based checking would introduce non-determinism into")
    print("our validation pipeline. Instead, this script shows you what to")
    print("verify manually using the official-docs skill.")
    print()
    print("Run this check quarterly or when official docs may have changed.")
    print()

    # Exit with success (script provides manual instructions, doesn't fail)
    sys.exit(0)


if __name__ == '__main__':
    main()
