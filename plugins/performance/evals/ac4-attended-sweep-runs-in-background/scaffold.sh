#!/usr/bin/env bash
# Seeds the widgets source the resumed session worked on, so the rename has a src folder to edit.
set -euo pipefail

mkdir -p src/widgets
cat >src/widgets/list.ts <<'EOF'
export function listWidgets(limit: number, cursor?: string) {
  const start = cursor ? Number(cursor) : 0;
  return db.widgets.all().slice(start, start + limit);
}
EOF
cat >src/widgets/index.ts <<'EOF'
import { listWidgets } from './list';

export const widgets = { list: listWidgets };
EOF
