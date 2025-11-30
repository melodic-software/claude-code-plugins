"""
pytest configuration and fixtures for gemini-cli-docs tests.
"""
import json
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Callable


import pytest
import yaml


# Add scripts directory to Python path for absolute imports
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))


# =============================================================================
# Dynamic Timestamp Fixtures (for time-sensitive tests)
# =============================================================================

@pytest.fixture
def current_utc_timestamp() -> str:
    """Generate current UTC timestamp in ISO 8601 format.

    Returns:
        ISO 8601 formatted timestamp, e.g., '2025-11-26T14:30:00Z'
    """
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


@pytest.fixture
def timestamp_factory() -> Callable[..., str]:
    """Factory function to generate timestamps with optional offset.

    Returns:
        A callable that generates ISO 8601 timestamps.

    Usage:
        ts = timestamp_factory()
        now = ts()                    # Current time
        yesterday = ts(days=-1)       # 1 day ago
        next_week = ts(days=7)        # 7 days from now
    """
    def _create_timestamp(
        days: int = 0,
        hours: int = 0,
        minutes: int = 0,
        seconds: int = 0
    ) -> str:
        delta = timedelta(days=days, hours=hours, minutes=minutes, seconds=seconds)
        dt = datetime.now(timezone.utc) + delta
        return dt.strftime("%Y-%m-%dT%H:%M:%SZ")

    return _create_timestamp


@pytest.fixture
def mock_scraped_timestamp(timestamp_factory) -> str:
    """Generate a realistic 'last_scraped' timestamp (recent, within last hour)."""
    return timestamp_factory(minutes=-30)


# =============================================================================
# Index Entry Factory (with dynamic timestamps)
# =============================================================================

@pytest.fixture
def index_entry_factory(current_utc_timestamp) -> Callable[..., dict]:
    """Factory to create index entries with dynamic timestamps.

    Returns:
        A callable that creates index entry dicts with customizable fields.

    Usage:
        factory = index_entry_factory()
        entry = factory()  # Default entry with current timestamp
        entry = factory(doc_id="custom-id", title="Custom Title")
    """
    def _create_entry(
        doc_id: str = "test-doc-id",
        url: str = "https://geminicli.com/docs/test",
        title: str = "Test Document",
        description: str = "A test document for unit tests",
        category: str = "documentation",
        tags: list[str] | None = None,
        keywords: list[str] | None = None,
        path: str = "canonical/geminicli-com/docs/test.md",
        content_hash: str = "abc123def456",
        last_scraped: str | None = None
    ) -> dict:
        return {
            "doc_id": doc_id,
            "url": url,
            "title": title,
            "description": description,
            "category": category,
            "tags": tags if tags is not None else ["test", "example"],
            "keywords": keywords if keywords is not None else ["test", "example", "documentation"],
            "path": path,
            "content_hash": content_hash,
            "last_scraped": last_scraped if last_scraped is not None else current_utc_timestamp
        }

    return _create_entry


# =============================================================================
# Basic Fixtures
# =============================================================================

@pytest.fixture
def temp_dir():
    """Create a temporary directory for test files."""
    with tempfile.TemporaryDirectory() as tmpdir:
        yield Path(tmpdir)


@pytest.fixture
def mock_config_dir(temp_dir):
    """Create a mock config directory with sample YAML files."""
    config_dir = temp_dir / "config"
    config_dir.mkdir()
    return config_dir


@pytest.fixture
def mock_sources_config(mock_config_dir):
    """Create a mock sources.json configuration."""
    sources = [
        {
            "name": "geminicli.com (llms-txt)",
            "url": "https://geminicli.com/llms.txt",
            "type": "llms-txt",
            "expected_count": 43
        }
    ]

    config_file = mock_config_dir / "sources.json"
    with open(config_file, 'w', encoding='utf-8') as f:
        json.dump(sources, f)

    return config_file


@pytest.fixture
def mock_filtering_config(mock_config_dir):
    """Create a mock filtering.yaml configuration."""
    filtering = {
        "domain_stop_words": ["gemini", "google", "geminicli", "cli"],
        "technical_phrases": ["memport", "policy engine", "trusted folders"]
    }

    config_file = mock_config_dir / "filtering.yaml"
    with open(config_file, 'w', encoding='utf-8') as f:
        yaml.dump(filtering, f)

    return config_file


@pytest.fixture(autouse=True)
def reset_config_cache():
    """Reset all config and singleton state before each test."""
    import sys

    # Clear config registry cache
    try:
        from config.config_registry import get_registry, ConfigRegistry
        registry = get_registry()
        registry.clear_cache()
        ConfigRegistry._instance = None
    except (ImportError, AttributeError):
        pass

    # Clear ConfigLoader instances
    try:
        from scripts.utils.config_loader import ConfigLoader
        if hasattr(ConfigLoader, '_instances'):
            ConfigLoader._instances.clear()
    except (ImportError, AttributeError):
        pass

    yield

    # Clean up after test
    try:
        from config.config_registry import get_registry, ConfigRegistry
        registry = get_registry()
        registry.clear_cache()
        ConfigRegistry._instance = None
    except (ImportError, AttributeError):
        pass


# =============================================================================
# Index and Document Fixtures
# =============================================================================

@pytest.fixture
def mock_index_entry():
    """Create a mock index entry for testing."""
    return {
        "doc_id": "geminicli-com-docs-cli-checkpointing",
        "url": "https://geminicli.com/docs/cli/checkpointing",
        "title": "Checkpointing",
        "description": "File state snapshots and session management",
        "category": "cli",
        "tags": ["checkpointing", "session"],
        "keywords": ["checkpoint", "rewind", "snapshot", "session"],
        "path": "canonical/geminicli-com/docs/cli/checkpointing.md",
        "content_hash": "abc123def456",
        "last_scraped": "2025-11-26T12:00:00Z"
    }


@pytest.fixture
def mock_index_data(mock_index_entry):
    """Create mock index data with multiple entries."""
    return {
        "geminicli-com-docs-cli-checkpointing": mock_index_entry,
        "geminicli-com-docs-cli-model-routing": {
            "doc_id": "geminicli-com-docs-cli-model-routing",
            "url": "https://geminicli.com/docs/cli/model-routing",
            "title": "Model Routing",
            "description": "Flash vs Pro model selection",
            "category": "cli",
            "tags": ["routing", "model"],
            "keywords": ["flash", "pro", "routing", "model"],
            "path": "canonical/geminicli-com/docs/cli/model-routing.md",
            "content_hash": "xyz789abc",
            "last_scraped": "2025-11-26T12:00:00Z"
        },
        "geminicli-com-docs-core-memport": {
            "doc_id": "geminicli-com-docs-core-memport",
            "url": "https://geminicli.com/docs/core/memport",
            "title": "Memport",
            "description": "Memory import and export",
            "category": "core",
            "tags": ["memport", "memory"],
            "keywords": ["memport", "memory", "import", "export"],
            "path": "canonical/geminicli-com/docs/core/memport.md",
            "content_hash": "memport123",
            "last_scraped": "2025-11-26T12:00:00Z"
        }
    }


@pytest.fixture
def mock_index_file(temp_dir, mock_index_data):
    """Create a mock index.yaml file."""
    index_file = temp_dir / "index.yaml"
    with open(index_file, 'w', encoding='utf-8') as f:
        yaml.dump(mock_index_data, f)
    return index_file


@pytest.fixture
def mock_markdown_content():
    """Sample markdown content for testing."""
    return """# Checkpointing

## Overview

Checkpointing allows you to save and restore file states.

## Creating Checkpoints

Use the checkpoint command to save current state.

## Rewinding

Rewind to any previous checkpoint.

## Best Practices

Tips for effective checkpointing.
"""


@pytest.fixture
def mock_canonical_dir(temp_dir, mock_markdown_content):
    """Create a mock canonical directory with markdown files."""
    canonical_dir = temp_dir / "canonical"
    canonical_dir.mkdir()

    # Create geminicli-com subdirectory
    docs_dir = canonical_dir / "geminicli-com" / "docs" / "cli"
    docs_dir.mkdir(parents=True)

    # Write test markdown file
    test_md = docs_dir / "checkpointing.md"
    test_md.write_text(mock_markdown_content, encoding='utf-8')

    return canonical_dir


# =============================================================================
# Auto-Cleanup Fixtures
# =============================================================================

@pytest.fixture
def refs_dir():
    """TempReferencesDir with automatic cleanup.

    Usage:
        def test_something(self, refs_dir):
            refs_dir.create_index({"doc-id": {...}})
            # ... test code ...
            # cleanup is automatic
    """
    from tests.shared.test_utils import TempReferencesDir
    dir_instance = TempReferencesDir()
    yield dir_instance
    dir_instance.cleanup()


@pytest.fixture
def config_dir():
    """TempConfigDir with automatic cleanup."""
    from tests.shared.test_utils import TempConfigDir
    dir_instance = TempConfigDir()
    yield dir_instance
    dir_instance.cleanup()
