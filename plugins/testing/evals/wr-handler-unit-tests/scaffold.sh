#!/usr/bin/env bash
# A Python service whose docs/testing.md co-locates unit tests beside the code and names them
# test_<action>_<outcome>_when_<condition>; a new create-template-item command handler has no tests.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main src docs pyproject.toml
mkdir -p src/templates docs
printf '[project]\nname = "templates"\nversion = "0.1.0"\n\n[tool.pytest.ini_options]\npython_files = ["*_test.py"]\n' >pyproject.toml
cat >docs/testing.md <<'EOF'
# Testing

- Framework: pytest with plain `assert`; no unittest classes.
- Unit tests sit beside the code they test: `src/<package>/<module>_test.py`.
- Name each test `test_<action>_<outcome>_when_<condition>`.
EOF
cat >src/templates/__init__.py <<'EOF'
EOF
cat >src/templates/create_template_item.py <<'EOF'
from dataclasses import dataclass


@dataclass(frozen=True)
class CreateTemplateItem:
    template_id: str
    name: str


class DuplicateItemName(Exception):
    pass


def handle(command: CreateTemplateItem, repository) -> str:
    name = command.name.strip()
    if not name:
        raise ValueError("name is required")
    if len(name) > 80:
        raise ValueError("name must be 80 characters or fewer")
    if repository.has_item_named(command.template_id, name):
        raise DuplicateItemName(name)
    return repository.add_item(command.template_id, name)
EOF
g add -A
g commit -q -m "create template item handler"
