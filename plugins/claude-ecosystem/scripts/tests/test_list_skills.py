"""Tests for list_skills.py script.

Tests cover:
- truncate_description(): First sentence extraction and length truncation
- parse_yaml_frontmatter(): YAML parsing without external dependencies
- Format functions: verbose, table, compact, minimal output formats
- CLI argument parsing: --format flag handling
"""

import sys
from io import StringIO
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

import pytest

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from list_skills import (
    truncate_description,
    parse_yaml_frontmatter,
    parse_skill_frontmatter,
    format_verbose,
    format_table,
    format_compact,
    format_minimal,
    find_skill_files,
    main,
)


class TestTruncateDescription:
    """Test suite for truncate_description function."""

    def test_first_sentence_with_period(self):
        """Extract first sentence ending with period."""
        desc = "This is the first sentence. This is the second."
        result = truncate_description(desc, max_len=80)
        assert result == "This is the first sentence."

    def test_first_sentence_with_exclamation(self):
        """Extract first sentence ending with exclamation mark."""
        desc = "This is exciting! More text follows."
        result = truncate_description(desc, max_len=80)
        assert result == "This is exciting!"

    def test_first_sentence_with_question(self):
        """Extract first sentence ending with question mark."""
        desc = "Is this a question? Yes it is."
        result = truncate_description(desc, max_len=80)
        assert result == "Is this a question?"

    def test_first_sentence_exceeds_max_len(self):
        """When first sentence exceeds max_len, truncate with ellipsis."""
        desc = "This is a very long first sentence that exceeds the maximum length limit."
        result = truncate_description(desc, max_len=30)
        assert len(result) <= 30
        assert result.endswith("...")

    def test_no_sentence_ending_truncates(self):
        """When no sentence ending found, fall back to truncation."""
        desc = "No sentence ending here just keeps going and going"
        result = truncate_description(desc, max_len=25)
        assert len(result) <= 25
        assert result.endswith("...")

    def test_short_description_unchanged(self):
        """Short description without sentence ending returned as-is."""
        desc = "Short desc"
        result = truncate_description(desc, max_len=80)
        assert result == "Short desc"

    def test_empty_string(self):
        """Empty string returns empty string."""
        result = truncate_description("", max_len=80)
        assert result == ""

    def test_word_boundary_preserved(self):
        """Truncation should not cut words in half."""
        desc = "Word boundary test here"
        result = truncate_description(desc, max_len=15)
        # Should cut at word boundary, not in middle of "boundary"
        assert "bound..." not in result or result == "Word..."

    def test_exact_max_len_sentence(self):
        """Sentence exactly at max_len is returned."""
        desc = "Exact."  # 6 chars
        result = truncate_description(desc, max_len=6)
        assert result == "Exact."

    def test_default_max_len(self):
        """Default max_len is 80."""
        long_desc = "A" * 100 + "."
        result = truncate_description(long_desc)
        # First sentence is too long, should truncate
        assert len(result) <= 80


class TestParseYamlFrontmatter:
    """Test suite for parse_yaml_frontmatter function."""

    def test_valid_frontmatter(self):
        """Parse valid YAML frontmatter."""
        content = """---
name: test-skill
description: A test skill
---
# Content here
"""
        result = parse_yaml_frontmatter(content)
        assert result["name"] == "test-skill"
        assert result["description"] == "A test skill"

    def test_missing_opening_delimiter(self):
        """Return empty dict when opening --- is missing."""
        content = """name: test-skill
description: A test skill
---
"""
        result = parse_yaml_frontmatter(content)
        assert result == {}

    def test_missing_closing_delimiter(self):
        """Return empty dict when closing --- is missing."""
        content = """---
name: test-skill
description: A test skill
"""
        result = parse_yaml_frontmatter(content)
        assert result == {}

    def test_double_quoted_values(self):
        """Parse double-quoted values correctly."""
        content = '''---
name: "quoted-name"
description: "A quoted description"
---
'''
        result = parse_yaml_frontmatter(content)
        assert result["name"] == "quoted-name"
        assert result["description"] == "A quoted description"

    def test_single_quoted_values(self):
        """Parse single-quoted values correctly."""
        content = """---
name: 'single-quoted'
description: 'Another description'
---
"""
        result = parse_yaml_frontmatter(content)
        assert result["name"] == "single-quoted"
        assert result["description"] == "Another description"

    def test_comments_ignored(self):
        """Comments in YAML are ignored."""
        content = """---
# This is a comment
name: test-skill
# Another comment
description: A test skill
---
"""
        result = parse_yaml_frontmatter(content)
        assert result["name"] == "test-skill"
        assert result["description"] == "A test skill"
        assert "#" not in result.get("name", "")

    def test_empty_frontmatter(self):
        """Empty frontmatter returns empty dict."""
        content = """---
---
"""
        result = parse_yaml_frontmatter(content)
        assert result == {}

    def test_value_with_colon(self):
        """Values containing colons are parsed correctly."""
        content = """---
name: test-skill
description: URL is https://example.com
---
"""
        result = parse_yaml_frontmatter(content)
        assert result["name"] == "test-skill"
        # Only first colon is used as separator
        assert "https" in result["description"]

    def test_whitespace_handling(self):
        """Whitespace around keys and values is trimmed."""
        content = """---
  name  :   test-skill
  description  :   A test skill
---
"""
        result = parse_yaml_frontmatter(content)
        assert result["name"] == "test-skill"
        assert result["description"] == "A test skill"


class TestParseSkillFrontmatter:
    """Test suite for parse_skill_frontmatter function."""

    def test_valid_skill_file(self):
        """Parse valid SKILL.md file."""
        with TemporaryDirectory() as tmpdir:
            skill_dir = Path(tmpdir) / "test-skill"
            skill_dir.mkdir()
            skill_file = skill_dir / "SKILL.md"
            skill_file.write_text("""---
name: my-skill
description: My skill description
---
# Content
""", encoding="utf-8")

            result = parse_skill_frontmatter(skill_file)
            assert result["name"] == "my-skill"
            assert result["description"] == "My skill description"

    def test_missing_name_uses_directory(self):
        """When name is missing, use directory name."""
        with TemporaryDirectory() as tmpdir:
            skill_dir = Path(tmpdir) / "fallback-name"
            skill_dir.mkdir()
            skill_file = skill_dir / "SKILL.md"
            skill_file.write_text("""---
description: A skill without name field
---
""", encoding="utf-8")

            result = parse_skill_frontmatter(skill_file)
            assert result["name"] == "fallback-name"

    def test_missing_description_default(self):
        """When description is missing, use default."""
        with TemporaryDirectory() as tmpdir:
            skill_dir = Path(tmpdir) / "test-skill"
            skill_dir.mkdir()
            skill_file = skill_dir / "SKILL.md"
            skill_file.write_text("""---
name: test-skill
---
""", encoding="utf-8")

            result = parse_skill_frontmatter(skill_file)
            assert result["description"] == "No description available"

    def test_nonexistent_file_returns_error(self):
        """Nonexistent file returns error description."""
        fake_path = Path("/nonexistent/path/SKILL.md")
        result = parse_skill_frontmatter(fake_path)
        assert "Error reading skill" in result["description"]


class TestFormatVerbose:
    """Test suite for format_verbose function."""

    def test_empty_skills(self):
        """Empty skills dict produces 'None found' sections."""
        skills = {"personal": [], "project": [], "plugin": []}
        result = format_verbose(skills)
        assert "*None found*" in result
        assert "Total: 0 skills" in result

    def test_with_personal_skills(self):
        """Personal skills are formatted correctly."""
        with TemporaryDirectory() as tmpdir:
            skill_dir = Path(tmpdir) / "my-skill"
            skill_dir.mkdir()
            skill_file = skill_dir / "SKILL.md"
            skill_file.write_text("""---
name: my-skill
description: Test description
---
""", encoding="utf-8")

            skills = {"personal": [skill_file], "project": [], "plugin": []}
            result = format_verbose(skills)

            assert "## Personal Skills" in result
            assert "### **my-skill**" in result
            assert "Test description" in result
            assert "Total: 1 skills" in result

    def test_with_plugin_skills(self):
        """Plugin skills include plugin name prefix."""
        with TemporaryDirectory() as tmpdir:
            skill_dir = Path(tmpdir) / "test-skill"
            skill_dir.mkdir()
            skill_file = skill_dir / "SKILL.md"
            skill_file.write_text("""---
name: test-skill
description: Plugin skill
---
""", encoding="utf-8")

            skills = {"personal": [], "project": [], "plugin": [("my-plugin", skill_file)]}
            result = format_verbose(skills)

            assert "## Plugin Skills" in result
            assert "### **my-plugin:test-skill**" in result


class TestFormatTable:
    """Test suite for format_table function."""

    def test_empty_skills_no_tables(self):
        """Empty skills dict produces no tables."""
        skills = {"personal": [], "project": [], "plugin": []}
        result = format_table(skills)
        assert "| Skill |" not in result
        assert "Total: 0 skills" in result

    def test_table_structure(self):
        """Tables have correct markdown structure."""
        with TemporaryDirectory() as tmpdir:
            skill_dir = Path(tmpdir) / "my-skill"
            skill_dir.mkdir()
            skill_file = skill_dir / "SKILL.md"
            skill_file.write_text("""---
name: my-skill
description: A short description.
---
""", encoding="utf-8")

            skills = {"personal": [skill_file], "project": [], "plugin": []}
            result = format_table(skills)

            assert "| Skill | Description |" in result
            assert "|-------|-------------|" in result
            assert "| **my-skill** |" in result

    def test_description_truncated(self):
        """Long descriptions are truncated in table format."""
        with TemporaryDirectory() as tmpdir:
            skill_dir = Path(tmpdir) / "my-skill"
            skill_dir.mkdir()
            skill_file = skill_dir / "SKILL.md"
            long_desc = "A" * 100 + " very long description."
            skill_file.write_text(f"""---
name: my-skill
description: {long_desc}
---
""", encoding="utf-8")

            skills = {"personal": [skill_file], "project": [], "plugin": []}
            result = format_table(skills)

            # Description should be truncated
            assert long_desc not in result
            assert "..." in result or "." in result


class TestFormatCompact:
    """Test suite for format_compact function."""

    def test_empty_skills(self):
        """Empty skills dict produces minimal output."""
        skills = {"personal": [], "project": [], "plugin": []}
        result = format_compact(skills)
        assert "Total: 0 skills" in result

    def test_plugin_grouping(self):
        """Plugin skills are grouped by plugin name."""
        with TemporaryDirectory() as tmpdir:
            skill_dir1 = Path(tmpdir) / "skill1"
            skill_dir1.mkdir()
            skill_file1 = skill_dir1 / "SKILL.md"
            skill_file1.write_text("""---
name: skill1
description: First skill
---
""", encoding="utf-8")

            skill_dir2 = Path(tmpdir) / "skill2"
            skill_dir2.mkdir()
            skill_file2 = skill_dir2 / "SKILL.md"
            skill_file2.write_text("""---
name: skill2
description: Second skill
---
""", encoding="utf-8")

            skills = {
                "personal": [],
                "project": [],
                "plugin": [("plugin-a", skill_file1), ("plugin-a", skill_file2)]
            }
            result = format_compact(skills)

            assert "*plugin-a:*" in result
            assert "**skill1**" in result
            assert "**skill2**" in result

    def test_inline_format(self):
        """Skills are formatted as inline list items."""
        with TemporaryDirectory() as tmpdir:
            skill_dir = Path(tmpdir) / "my-skill"
            skill_dir.mkdir()
            skill_file = skill_dir / "SKILL.md"
            skill_file.write_text("""---
name: my-skill
description: My description
---
""", encoding="utf-8")

            skills = {"personal": [skill_file], "project": [], "plugin": []}
            result = format_compact(skills)

            assert "- **my-skill** - " in result


class TestFormatMinimal:
    """Test suite for format_minimal function."""

    def test_empty_skills(self):
        """Empty skills produces minimal output."""
        skills = {"personal": [], "project": [], "plugin": []}
        result = format_minimal(skills)
        assert "Total: 0 skills" in result

    def test_flat_alphabetical_list(self):
        """Skills are listed alphabetically in flat format."""
        with TemporaryDirectory() as tmpdir:
            # Create skills with names that would sort differently
            for name in ["zebra", "alpha", "beta"]:
                skill_dir = Path(tmpdir) / name
                skill_dir.mkdir()
                skill_file = skill_dir / "SKILL.md"
                skill_file.write_text(f"""---
name: {name}
description: {name} description
---
""", encoding="utf-8")

            skill_files = [Path(tmpdir) / n / "SKILL.md" for n in ["zebra", "alpha", "beta"]]
            skills = {"personal": skill_files, "project": [], "plugin": []}
            result = format_minimal(skills)

            # Find positions of each skill name
            alpha_pos = result.find("**alpha**")
            beta_pos = result.find("**beta**")
            zebra_pos = result.find("**zebra**")

            # Should be in alphabetical order
            assert alpha_pos < beta_pos < zebra_pos

    def test_plugin_prefix_included(self):
        """Plugin skills include plugin name prefix."""
        with TemporaryDirectory() as tmpdir:
            skill_dir = Path(tmpdir) / "my-skill"
            skill_dir.mkdir()
            skill_file = skill_dir / "SKILL.md"
            skill_file.write_text("""---
name: my-skill
description: My description
---
""", encoding="utf-8")

            skills = {"personal": [], "project": [], "plugin": [("my-plugin", skill_file)]}
            result = format_minimal(skills)

            assert "**my-plugin:my-skill**" in result

    def test_very_brief_descriptions(self):
        """Descriptions are truncated to ~50 chars."""
        with TemporaryDirectory() as tmpdir:
            skill_dir = Path(tmpdir) / "my-skill"
            skill_dir.mkdir()
            skill_file = skill_dir / "SKILL.md"
            long_desc = "A" * 100 + " very long description that exceeds limits."
            skill_file.write_text(f"""---
name: my-skill
description: {long_desc}
---
""", encoding="utf-8")

            skills = {"personal": [skill_file], "project": [], "plugin": []}
            result = format_minimal(skills)

            # Full description should not appear
            assert long_desc not in result


class TestCLIArgumentParsing:
    """Test suite for CLI argument parsing."""

    def test_default_format_is_verbose(self):
        """Default format without --format flag is verbose."""
        with patch("list_skills.find_skill_files") as mock_find:
            mock_find.return_value = {"personal": [], "project": [], "plugin": []}
            with patch("sys.argv", ["list_skills.py"]):
                with patch("sys.stdout", new_callable=StringIO) as mock_stdout:
                    main()
                    output = mock_stdout.getvalue()
                    # Verbose format has ## headers
                    assert "## Personal Skills" in output

    def test_format_table(self):
        """--format=table produces table output."""
        with patch("list_skills.find_skill_files") as mock_find:
            mock_find.return_value = {"personal": [], "project": [], "plugin": []}
            with patch("sys.argv", ["list_skills.py", "--format=table"]):
                with patch("sys.stdout", new_callable=StringIO) as mock_stdout:
                    main()
                    output = mock_stdout.getvalue()
                    # Table format doesn't have "## Personal Skills" when empty
                    assert "Total: 0 skills" in output

    def test_format_compact(self):
        """--format=compact produces compact output."""
        with patch("list_skills.find_skill_files") as mock_find:
            mock_find.return_value = {"personal": [], "project": [], "plugin": []}
            with patch("sys.argv", ["list_skills.py", "--format=compact"]):
                with patch("sys.stdout", new_callable=StringIO) as mock_stdout:
                    main()
                    output = mock_stdout.getvalue()
                    assert "Total: 0 skills" in output

    def test_format_minimal(self):
        """--format=minimal produces minimal output."""
        with patch("list_skills.find_skill_files") as mock_find:
            mock_find.return_value = {"personal": [], "project": [], "plugin": []}
            with patch("sys.argv", ["list_skills.py", "--format=minimal"]):
                with patch("sys.stdout", new_callable=StringIO) as mock_stdout:
                    main()
                    output = mock_stdout.getvalue()
                    assert "Total: 0 skills" in output

    def test_short_flag_f(self):
        """-f shorthand works like --format."""
        with patch("list_skills.find_skill_files") as mock_find:
            mock_find.return_value = {"personal": [], "project": [], "plugin": []}
            with patch("sys.argv", ["list_skills.py", "-f", "minimal"]):
                with patch("sys.stdout", new_callable=StringIO) as mock_stdout:
                    main()
                    output = mock_stdout.getvalue()
                    assert "Total: 0 skills" in output

    def test_invalid_format_exits(self):
        """Invalid format option causes argparse error."""
        with patch("sys.argv", ["list_skills.py", "--format=invalid"]):
            with pytest.raises(SystemExit):
                main()


class TestFindSkillFiles:
    """Test suite for find_skill_files function."""

    def test_returns_dict_structure(self):
        """Returns dict with personal, project, plugin keys."""
        result = find_skill_files()
        assert "personal" in result
        assert "project" in result
        assert "plugin" in result
        assert isinstance(result["personal"], list)
        assert isinstance(result["project"], list)
        assert isinstance(result["plugin"], list)

    def test_deduplication(self):
        """Same skill file is not included twice."""
        # This is tested implicitly by the seen_paths set in the function
        # We just verify the function doesn't crash with overlapping paths
        result = find_skill_files()
        all_paths = set()
        for skill_file in result["personal"]:
            path = skill_file.resolve()
            assert path not in all_paths, f"Duplicate found: {path}"
            all_paths.add(path)
        for skill_file in result["project"]:
            path = skill_file.resolve()
            assert path not in all_paths, f"Duplicate found: {path}"
            all_paths.add(path)
        for _, skill_file in result["plugin"]:
            path = skill_file.resolve()
            assert path not in all_paths, f"Duplicate found: {path}"
            all_paths.add(path)
