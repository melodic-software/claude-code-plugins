"""Bring a shared session file up to the current schemaVersion.

`MIGRATIONS[n]` takes a version-n document to version n+1 as a pure dict -> dict function;
`migrate` runs them in order and stamps each step's version. It never mutates its input.
"""

CURRENT = 1
MIGRATIONS = {}


class MigrationError(ValueError):
    """The document cannot be brought to the current version."""


def migrate(doc):
    version = doc.get("schemaVersion")
    if isinstance(version, bool) or not isinstance(version, int) or version < 1:
        raise MigrationError(
            f"schemaVersion must be a positive integer, got {version!r}"
        )
    if version > CURRENT:
        raise MigrationError(
            f"state.json has schemaVersion {version}, newer than {CURRENT}, the newest this plugin reads; update the plugin"
        )
    while version < CURRENT:
        step = MIGRATIONS.get(version)
        if step is None:
            raise MigrationError(
                f"no migration from schemaVersion {version} to {version + 1}"
            )
        version += 1
        doc = {**step(doc), "schemaVersion": version}
    return doc
