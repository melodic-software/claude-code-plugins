#!/usr/bin/env python3
"""List all available Claude Code skills from all sources.

This script scans personal, project, and plugin skill directories
and outputs a formatted markdown list of all available skills.

Usage:
    python list_skills.py                    # Default verbose format
    python list_skills.py --format=table     # Grouped tables (compact)
    python list_skills.py --format=compact   # First sentence, inline
    python list_skills.py --format=minimal   # Name + brief summary
"""

import argparse
import re
import sys
from pathlib import Path


def truncate_description(desc: str, max_len: int = 80) -> str:
    """Truncate description to first sentence or max length."""
    # Find first sentence
    match = re.match(r'^[^.!?]*[.!?]', desc)
    if match:
        first_sentence = match.group(0).strip()
        if len(first_sentence) <= max_len:
            return first_sentence
    # Fall back to truncation
    if len(desc) <= max_len:
        return desc
    return desc[:max_len - 3].rsplit(' ', 1)[0] + '...'


def parse_yaml_frontmatter(content: str) -> dict:
    """Parse simple YAML frontmatter without external dependencies."""
    result = {}
    if not content.startswith('---'):
        return result

    end = content.find('---', 3)
    if end == -1:
        return result

    yaml_content = content[3:end].strip()
    for line in yaml_content.split('\n'):
        line = line.strip()
        if ':' in line and not line.startswith('#'):
            key, _, value = line.partition(':')
            key = key.strip()
            value = value.strip()
            # Remove quotes if present
            if value.startswith('"') and value.endswith('"'):
                value = value[1:-1]
            elif value.startswith("'") and value.endswith("'"):
                value = value[1:-1]
            result[key] = value

    return result


def find_skill_files() -> dict:
    """Find all SKILL.md files from all skill sources."""
    skills = {'personal': [], 'project': [], 'plugin': []}
    seen_paths = set()  # Avoid duplicates

    # Personal skills: ~/.claude/skills/*/SKILL.md
    personal_dir = Path.home() / '.claude' / 'skills'
    if personal_dir.exists():
        for item in personal_dir.iterdir():
            if item.is_dir():
                skill_file = item / 'SKILL.md'
                if skill_file.exists():
                    skills['personal'].append(skill_file)
                    seen_paths.add(skill_file.resolve())

    # Project skills: .claude/skills/*/SKILL.md (from cwd)
    project_dir = Path.cwd() / '.claude' / 'skills'
    if project_dir.exists():
        for item in project_dir.iterdir():
            if item.is_dir():
                skill_file = item / 'SKILL.md'
                if skill_file.exists() and skill_file.resolve() not in seen_paths:
                    skills['project'].append(skill_file)
                    seen_paths.add(skill_file.resolve())

    # Plugin skills: ~/.claude/plugins/marketplaces/*/*/skills/*/SKILL.md
    plugins_dir = Path.home() / '.claude' / 'plugins' / 'marketplaces'
    if plugins_dir.exists():
        for marketplace in plugins_dir.iterdir():
            if not marketplace.is_dir():
                continue
            for plugin in marketplace.iterdir():
                if not plugin.is_dir():
                    continue
                skills_dir = plugin / 'skills'
                if skills_dir.exists():
                    for skill_dir in skills_dir.iterdir():
                        if skill_dir.is_dir():
                            skill_file = skill_dir / 'SKILL.md'
                            if skill_file.exists() and skill_file.resolve() not in seen_paths:
                                # Include plugin name for namespacing
                                skills['plugin'].append((plugin.name, skill_file))
                                seen_paths.add(skill_file.resolve())

    # Development mode: also scan ./plugins/*/skills/ for plugin development repos
    dev_plugins_dir = Path.cwd() / 'plugins'
    if dev_plugins_dir.exists():
        for plugin in dev_plugins_dir.iterdir():
            if not plugin.is_dir():
                continue
            skills_dir = plugin / 'skills'
            if skills_dir.exists():
                for skill_dir in skills_dir.iterdir():
                    if skill_dir.is_dir():
                        skill_file = skill_dir / 'SKILL.md'
                        if skill_file.exists() and skill_file.resolve() not in seen_paths:
                            skills['plugin'].append((plugin.name, skill_file))
                            seen_paths.add(skill_file.resolve())

    return skills


def parse_skill_frontmatter(skill_file: Path) -> dict:
    """Extract name and description from SKILL.md YAML frontmatter."""
    try:
        content = skill_file.read_text(encoding='utf-8')
        frontmatter = parse_yaml_frontmatter(content)
        return {
            'name': frontmatter.get('name', skill_file.parent.name),
            'description': frontmatter.get('description', 'No description available')
        }
    except Exception as e:
        return {'name': skill_file.parent.name, 'description': f'Error reading skill: {e}'}


def format_verbose(skills: dict) -> str:
    """Format skills as verbose markdown (original format)."""
    output = []
    counts = {'personal': 0, 'project': 0, 'plugin': 0}

    # Personal skills
    output.append("## Personal Skills (~/.claude/skills/)\n")
    if skills['personal']:
        for skill_file in sorted(skills['personal'], key=lambda f: f.parent.name.lower()):
            info = parse_skill_frontmatter(skill_file)
            output.append(f"### **{info['name']}**")
            output.append(f"{info['description']}\n")
            output.append("---\n")
            counts['personal'] += 1
    else:
        output.append("*None found*\n")
        output.append("---\n")

    # Project skills
    output.append("## Project Skills (.claude/skills/)\n")
    if skills['project']:
        for skill_file in sorted(skills['project'], key=lambda f: f.parent.name.lower()):
            info = parse_skill_frontmatter(skill_file)
            output.append(f"### **{info['name']}**")
            output.append(f"{info['description']}\n")
            output.append("---\n")
            counts['project'] += 1
    else:
        output.append("*None found*\n")
        output.append("---\n")

    # Plugin skills
    output.append("## Plugin Skills\n")
    if skills['plugin']:
        for plugin_name, skill_file in sorted(skills['plugin'], key=lambda x: f"{x[0]}:{x[1].parent.name}".lower()):
            info = parse_skill_frontmatter(skill_file)
            output.append(f"### **{plugin_name}:{info['name']}**")
            output.append(f"{info['description']}\n")
            output.append("---\n")
            counts['plugin'] += 1
    else:
        output.append("*None found*\n")
        output.append("---\n")

    # Summary
    total = counts['personal'] + counts['project'] + counts['plugin']
    output.append(f"\n**Total: {total} skills** ({counts['personal']} personal, {counts['project']} project, {counts['plugin']} plugin)")

    return '\n'.join(output)


def format_table(skills: dict) -> str:
    """Format skills as grouped markdown tables."""
    output = []
    counts = {'personal': 0, 'project': 0, 'plugin': 0}

    # Personal skills
    if skills['personal']:
        output.append("## Personal Skills\n")
        output.append("| Skill | Description |")
        output.append("|-------|-------------|")
        for skill_file in sorted(skills['personal'], key=lambda f: f.parent.name.lower()):
            info = parse_skill_frontmatter(skill_file)
            desc = truncate_description(info['description'], 60)
            output.append(f"| **{info['name']}** | {desc} |")
            counts['personal'] += 1
        output.append("")

    # Project skills
    if skills['project']:
        output.append("## Project Skills\n")
        output.append("| Skill | Description |")
        output.append("|-------|-------------|")
        for skill_file in sorted(skills['project'], key=lambda f: f.parent.name.lower()):
            info = parse_skill_frontmatter(skill_file)
            desc = truncate_description(info['description'], 60)
            output.append(f"| **{info['name']}** | {desc} |")
            counts['project'] += 1
        output.append("")

    # Plugin skills - group by plugin
    if skills['plugin']:
        # Group by plugin name
        by_plugin = {}
        for plugin_name, skill_file in skills['plugin']:
            if plugin_name not in by_plugin:
                by_plugin[plugin_name] = []
            by_plugin[plugin_name].append(skill_file)

        output.append("## Plugin Skills\n")
        for plugin_name in sorted(by_plugin.keys()):
            output.append(f"### {plugin_name}\n")
            output.append("| Skill | Description |")
            output.append("|-------|-------------|")
            for skill_file in sorted(by_plugin[plugin_name], key=lambda f: f.parent.name.lower()):
                info = parse_skill_frontmatter(skill_file)
                desc = truncate_description(info['description'], 60)
                output.append(f"| **{info['name']}** | {desc} |")
                counts['plugin'] += 1
            output.append("")

    # Summary
    total = counts['personal'] + counts['project'] + counts['plugin']
    output.append(f"**Total: {total} skills** ({counts['personal']} personal, {counts['project']} project, {counts['plugin']} plugin)")

    return '\n'.join(output)


def format_compact(skills: dict) -> str:
    """Format skills as compact inline list with first sentence descriptions."""
    output = []
    counts = {'personal': 0, 'project': 0, 'plugin': 0}

    # Personal skills
    if skills['personal']:
        output.append("**Personal:**")
        for skill_file in sorted(skills['personal'], key=lambda f: f.parent.name.lower()):
            info = parse_skill_frontmatter(skill_file)
            desc = truncate_description(info['description'], 70)
            output.append(f"- **{info['name']}** - {desc}")
            counts['personal'] += 1
        output.append("")

    # Project skills
    if skills['project']:
        output.append("**Project:**")
        for skill_file in sorted(skills['project'], key=lambda f: f.parent.name.lower()):
            info = parse_skill_frontmatter(skill_file)
            desc = truncate_description(info['description'], 70)
            output.append(f"- **{info['name']}** - {desc}")
            counts['project'] += 1
        output.append("")

    # Plugin skills - group by plugin
    if skills['plugin']:
        by_plugin = {}
        for plugin_name, skill_file in skills['plugin']:
            if plugin_name not in by_plugin:
                by_plugin[plugin_name] = []
            by_plugin[plugin_name].append(skill_file)

        output.append("**Plugins:**")
        for plugin_name in sorted(by_plugin.keys()):
            output.append(f"*{plugin_name}:*")
            for skill_file in sorted(by_plugin[plugin_name], key=lambda f: f.parent.name.lower()):
                info = parse_skill_frontmatter(skill_file)
                desc = truncate_description(info['description'], 60)
                output.append(f"  - **{info['name']}** - {desc}")
                counts['plugin'] += 1
        output.append("")

    # Summary
    total = counts['personal'] + counts['project'] + counts['plugin']
    output.append(f"**Total: {total} skills**")

    return '\n'.join(output)


def format_minimal(skills: dict) -> str:
    """Format skills as minimal list with very brief descriptions."""
    output = []
    count = 0

    all_skills = []

    # Collect all skills
    for skill_file in skills['personal']:
        info = parse_skill_frontmatter(skill_file)
        all_skills.append((info['name'], info['description'], 'personal'))

    for skill_file in skills['project']:
        info = parse_skill_frontmatter(skill_file)
        all_skills.append((info['name'], info['description'], 'project'))

    for plugin_name, skill_file in skills['plugin']:
        info = parse_skill_frontmatter(skill_file)
        all_skills.append((f"{plugin_name}:{info['name']}", info['description'], 'plugin'))

    # Sort and output
    for name, desc, _ in sorted(all_skills, key=lambda x: x[0].lower()):
        brief = truncate_description(desc, 50)
        output.append(f"- **{name}**: {brief}")
        count += 1

    output.append(f"\n**Total: {count} skills**")
    return '\n'.join(output)


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='List all available Claude Code skills',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Formats:
  verbose   Full descriptions with separators (default)
  table     Grouped markdown tables with truncated descriptions
  compact   Inline list with first sentence descriptions
  minimal   Flat list with very brief descriptions (~50 chars)
'''
    )
    parser.add_argument(
        '--format', '-f',
        choices=['verbose', 'table', 'compact', 'minimal'],
        default='verbose',
        help='Output format (default: verbose)'
    )

    args = parser.parse_args()
    skills = find_skill_files()

    if args.format == 'table':
        print(format_table(skills))
    elif args.format == 'compact':
        print(format_compact(skills))
    elif args.format == 'minimal':
        print(format_minimal(skills))
    else:
        print(format_verbose(skills))

    return 0


if __name__ == '__main__':
    sys.exit(main())
