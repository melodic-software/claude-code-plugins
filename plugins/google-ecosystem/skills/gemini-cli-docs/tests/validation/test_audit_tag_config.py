"""
Tests for audit_tag_config.py script.

Tests the GeminiTagConfigAuditor class for auditing tag configurations.
"""

from tests.shared.test_utils import TempReferencesDir, TempConfigDir, create_mock_index_entry


class TestGeminiTagConfigAuditor:
    """Test suite for GeminiTagConfigAuditor"""

    def test_audit_full(self, temp_dir):
        """Test full audit including tag coverage and usage"""
        refs_dir = TempReferencesDir()
        config_dir = TempConfigDir()
        try:
            # Create a minimal tag detection config
            config_dir.create_tag_detection_yaml({
                'tags': {
                    'cli': {'keywords': ['command', 'terminal']},
                    'features': {'keywords': ['checkpointing', 'sandbox']}
                }
            })

            # Create index with entries
            index = {
                'test-doc': create_mock_index_entry(
                    'test-doc',
                    'https://geminicli.com/docs/test',
                    'geminicli-com/docs/test.md',
                    tags=['cli']
                )
            }
            refs_dir.create_index(index)

            from scripts.validation.audit_tag_config import GeminiTagConfigAuditor

            auditor = GeminiTagConfigAuditor(refs_dir.references_dir, config_dir.config_dir)

            # Should be able to run full audit
            result = auditor.audit()

            # Result should be a dictionary with audit results
            assert isinstance(result, dict)
            assert 'tag_coverage' in result
            assert 'tag_usage' in result
        finally:
            refs_dir.cleanup()
            config_dir.cleanup()

    def test_audit_tag_coverage(self, temp_dir):
        """Test tag coverage analysis in audit"""
        refs_dir = TempReferencesDir()
        config_dir = TempConfigDir()
        try:
            config_dir.create_tag_detection_yaml({
                'tags': {
                    'cli': {'keywords': ['command']},
                    'features': {'keywords': ['feature']}
                }
            })

            index = {
                'cli-doc': create_mock_index_entry(
                    'cli-doc',
                    'https://geminicli.com/docs/cli/commands',
                    'geminicli-com/docs/cli/commands.md',
                    tags=['cli']
                )
            }
            refs_dir.create_index(index)

            from scripts.validation.audit_tag_config import GeminiTagConfigAuditor

            auditor = GeminiTagConfigAuditor(refs_dir.references_dir, config_dir.config_dir)

            # Run full audit
            result = auditor.audit()

            assert isinstance(result, dict)
            assert 'tag_coverage' in result
            assert 'tag_distribution' in result['tag_coverage']
        finally:
            refs_dir.cleanup()
            config_dir.cleanup()

    def test_auditor_initialization(self, temp_dir):
        """Test auditor initialization with base_dir and config_dir"""
        refs_dir = TempReferencesDir()
        config_dir = TempConfigDir()
        try:
            refs_dir.create_index({})

            from scripts.validation.audit_tag_config import GeminiTagConfigAuditor

            auditor = GeminiTagConfigAuditor(refs_dir.references_dir, config_dir.config_dir)

            # Should initialize with correct paths
            assert auditor.base_dir == refs_dir.references_dir
            assert auditor.config_dir == config_dir.config_dir
        finally:
            refs_dir.cleanup()
            config_dir.cleanup()

    def test_auditor_with_empty_index(self, temp_dir):
        """Test auditor behavior with empty index"""
        refs_dir = TempReferencesDir()
        config_dir = TempConfigDir()
        try:
            # Empty index
            refs_dir.create_index({})

            from scripts.validation.audit_tag_config import GeminiTagConfigAuditor

            auditor = GeminiTagConfigAuditor(refs_dir.references_dir, config_dir.config_dir)

            # Should handle empty index gracefully
            assert auditor.entries == []
        finally:
            refs_dir.cleanup()
            config_dir.cleanup()
