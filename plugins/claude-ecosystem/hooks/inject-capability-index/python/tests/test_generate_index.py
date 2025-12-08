#!/usr/bin/env python3
"""Tests for generate_index.py - Capability index generation."""

import json
import sys
from pathlib import Path

import pytest

# Add parent directory to path for imports
parent_dir = Path(__file__).parent.parent
sys.path.insert(0, str(parent_dir))

from generate_index import (
    normalize_path,
    find_plugins_dir,
    scan_plugin,
    scan_all_plugins,
    format_minimal,
    format_standard,
    format_comprehensive,
    format_index,
    estimate_tokens,
)


class TestNormalizePath:
    """Tests for MSYS path normalization."""

    def test_unix_path_unchanged(self):
        """Normal Unix paths should be unchanged."""
        result = normalize_path("/home/user/project")
        assert str(result) == "/home/user/project" or result == Path("/home/user/project")

    def test_windows_path_unchanged(self):
        """Windows paths should be unchanged."""
        result = normalize_path("C:/Users/test")
        assert "Users" in str(result) and "test" in str(result)

    @pytest.mark.skipif(sys.platform != "win32", reason="MSYS paths only on Windows")
    def test_msys_path_converted(self):
        """MSYS-style paths should be converted on Windows."""
        result = normalize_path("/d/repos/project")
        assert str(result).upper().startswith("D:")


class TestFindPluginsDir:
    """Tests for plugins directory discovery."""

    def test_returns_path_or_none(self):
        """Should return Path or None."""
        result = find_plugins_dir()
        assert result is None or isinstance(result, Path)


class TestScanPlugin:
    """Tests for individual plugin scanning."""

    def test_nonexistent_plugin(self, tmp_path):
        """Non-existent plugin directory should return None."""
        result = scan_plugin(tmp_path / "nonexistent")
        assert result is None

    def test_empty_plugin(self, tmp_path):
        """Plugin with no capabilities should return None."""
        plugin_dir = tmp_path / "empty-plugin"
        plugin_dir.mkdir()
        result = scan_plugin(plugin_dir)
        assert result is None

    def test_plugin_with_skill(self, tmp_path):
        """Plugin with valid skill should be scanned."""
        plugin_dir = tmp_path / "test-plugin"
        plugin_dir.mkdir()

        # Create plugin.json
        plugin_json_dir = plugin_dir / ".claude-plugin"
        plugin_json_dir.mkdir()
        plugin_json = plugin_json_dir / "plugin.json"
        plugin_json.write_text(json.dumps({
            "name": "test-plugin",
            "description": "A test plugin"
        }), encoding='utf-8')

        # Create skill
        skills_dir = plugin_dir / "skills" / "test-skill"
        skills_dir.mkdir(parents=True)
        skill_md = skills_dir / "SKILL.md"
        skill_md.write_text("""---
name: test-skill
description: A test skill for testing purposes
allowed-tools: Read, Write
---

# Test Skill
""", encoding='utf-8')

        result = scan_plugin(plugin_dir)
        assert result is not None
        assert result["name"] == "test-plugin"
        assert len(result["skills"]) == 1
        assert result["skills"][0]["name"] == "test-skill"

    def test_plugin_with_agent(self, tmp_path):
        """Plugin with valid agent should be scanned."""
        plugin_dir = tmp_path / "test-plugin"
        plugin_dir.mkdir()

        # Create agent
        agents_dir = plugin_dir / "agents"
        agents_dir.mkdir()
        agent_md = agents_dir / "test-agent.md"
        agent_md.write_text("""---
name: test-agent
description: A test agent
model: haiku
tools: Read, Grep
---

# Test Agent
""", encoding='utf-8')

        result = scan_plugin(plugin_dir)
        assert result is not None
        assert len(result["agents"]) == 1
        assert result["agents"][0]["name"] == "test-agent"
        assert result["agents"][0]["model"] == "haiku"

    def test_plugin_with_command(self, tmp_path):
        """Plugin with valid command should be scanned."""
        plugin_dir = tmp_path / "test-plugin"
        plugin_dir.mkdir()

        # Create command
        commands_dir = plugin_dir / "commands"
        commands_dir.mkdir()
        cmd_md = commands_dir / "test-cmd.md"
        cmd_md.write_text("""---
description: A test command
---

# Test Command
""", encoding='utf-8')

        result = scan_plugin(plugin_dir)
        assert result is not None
        assert len(result["commands"]) == 1
        assert result["commands"][0]["name"] == "test-cmd"

    def test_malformed_plugin_json_warning(self, tmp_path, capsys):
        """Malformed plugin.json should log warning to stderr."""
        plugin_dir = tmp_path / "bad-plugin"
        plugin_dir.mkdir()

        # Create malformed plugin.json
        plugin_json_dir = plugin_dir / ".claude-plugin"
        plugin_json_dir.mkdir()
        plugin_json = plugin_json_dir / "plugin.json"
        plugin_json.write_text("{ invalid json", encoding='utf-8')

        # Create skill so plugin isn't empty
        skills_dir = plugin_dir / "skills" / "test-skill"
        skills_dir.mkdir(parents=True)
        skill_md = skills_dir / "SKILL.md"
        skill_md.write_text("""---
name: test-skill
description: Test
---
""", encoding='utf-8')

        result = scan_plugin(plugin_dir)

        # Should still return plugin (uses directory name as fallback)
        assert result is not None
        assert result["name"] == "bad-plugin"

        # Should have logged warning
        captured = capsys.readouterr()
        assert "Warning" in captured.err or "Invalid JSON" in captured.err


class TestScanAllPlugins:
    """Tests for scanning all plugins."""

    def test_empty_plugins_dir(self, tmp_path):
        """Empty plugins directory should return empty list."""
        result = scan_all_plugins(tmp_path)
        assert result == []

    def test_nonexistent_plugins_dir(self, tmp_path):
        """Non-existent plugins directory should return empty list."""
        result = scan_all_plugins(tmp_path / "nonexistent")
        assert result == []

    def test_multiple_plugins(self, tmp_path):
        """Multiple plugins should all be scanned."""
        # Create plugin 1
        plugin1 = tmp_path / "plugin-a"
        plugin1.mkdir()
        skills1 = plugin1 / "skills" / "skill-a"
        skills1.mkdir(parents=True)
        (skills1 / "SKILL.md").write_text("---\nname: skill-a\ndescription: A\n---", encoding='utf-8')

        # Create plugin 2
        plugin2 = tmp_path / "plugin-b"
        plugin2.mkdir()
        skills2 = plugin2 / "skills" / "skill-b"
        skills2.mkdir(parents=True)
        (skills2 / "SKILL.md").write_text("---\nname: skill-b\ndescription: B\n---", encoding='utf-8')

        result = scan_all_plugins(tmp_path)
        assert len(result) == 2
        names = [p["name"] for p in result]
        assert "plugin-a" in names
        assert "plugin-b" in names

    def test_hidden_dirs_skipped(self, tmp_path):
        """Directories starting with . should be skipped."""
        # Create hidden plugin
        hidden = tmp_path / ".hidden-plugin"
        hidden.mkdir()
        skills = hidden / "skills" / "test"
        skills.mkdir(parents=True)
        (skills / "SKILL.md").write_text("---\nname: test\ndescription: T\n---", encoding='utf-8')

        result = scan_all_plugins(tmp_path)
        assert len(result) == 0


class TestFormatMinimal:
    """Tests for minimal format output."""

    def test_empty_plugins(self):
        """Empty plugins list should produce minimal output."""
        result = format_minimal([])
        assert "<capability-index>" in result
        assert "</capability-index>" in result
        assert "CAPABILITIES (0 skills, 0 agents, 0 commands)" in result

    def test_plugin_counted(self):
        """Plugins should be counted correctly."""
        plugins = [{
            "name": "test",
            "description": "",
            "skills": [{"name": "s1", "short_desc": "Skill 1", "description": "", "keywords": [], "tools": ""}],
            "agents": [{"name": "a1", "short_desc": "Agent 1", "description": "", "model": "sonnet", "tools": ""}],
            "commands": [{"name": "c1", "description": "Cmd 1"}]
        }]
        result = format_minimal(plugins)
        assert "1 skills" in result
        assert "1 agents" in result
        assert "1 commands" in result


class TestFormatStandard:
    """Tests for standard format output."""

    def test_includes_keywords(self):
        """Standard format should include keywords."""
        plugins = [{
            "name": "test",
            "description": "",
            "skills": [{
                "name": "s1",
                "short_desc": "A skill",
                "description": "",
                "keywords": ["claude", "hooks"],
                "tools": ""
            }],
            "agents": [],
            "commands": []
        }]
        result = format_standard(plugins)
        assert "KW:" in result
        assert "claude" in result

    def test_includes_model(self):
        """Standard format should include agent model."""
        plugins = [{
            "name": "test",
            "description": "",
            "skills": [],
            "agents": [{
                "name": "a1",
                "short_desc": "An agent",
                "description": "",
                "model": "haiku",
                "tools": ""
            }],
            "commands": []
        }]
        result = format_standard(plugins)
        assert "(haiku)" in result


class TestFormatComprehensive:
    """Tests for comprehensive format output."""

    def test_includes_quick_reference(self):
        """Comprehensive format should include quick reference table."""
        result = format_comprehensive([])
        assert "Quick Reference" in result
        assert "docs-management" in result

    def test_includes_tools(self):
        """Comprehensive format should include tools."""
        plugins = [{
            "name": "test",
            "description": "A test plugin",
            "skills": [{
                "name": "s1",
                "short_desc": "A skill",
                "description": "Full description here",
                "keywords": ["test"],
                "tools": "Read, Write, Grep"
            }],
            "agents": [],
            "commands": []
        }]
        result = format_comprehensive(plugins)
        assert "Tools:" in result
        assert "Read, Write, Grep" in result


class TestFormatIndex:
    """Tests for format_index dispatcher."""

    def test_minimal_level(self):
        """Should dispatch to minimal formatter."""
        result = format_index([], "minimal")
        assert "CAPABILITIES" in result

    def test_standard_level(self):
        """Should dispatch to standard formatter."""
        result = format_index([], "standard")
        assert "INSTALLED CAPABILITIES" in result

    def test_comprehensive_level(self):
        """Should dispatch to comprehensive formatter."""
        result = format_index([], "comprehensive")
        assert "COMPLETE CAPABILITY INDEX" in result

    def test_default_is_standard(self):
        """Default should be standard."""
        result = format_index([])
        assert "INSTALLED CAPABILITIES" in result


class TestEstimateTokens:
    """Tests for token estimation."""

    def test_empty_string(self):
        """Empty string should be 0 tokens."""
        assert estimate_tokens("") == 0

    def test_estimate_approximation(self):
        """Token estimate should be roughly chars/4."""
        text = "a" * 400
        result = estimate_tokens(text)
        assert result == 100  # 400 / 4


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
