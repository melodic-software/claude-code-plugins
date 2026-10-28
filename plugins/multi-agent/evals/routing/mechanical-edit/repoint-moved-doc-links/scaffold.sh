#!/usr/bin/env bash
# Stages the routing rubric at its new path and four docs that still link to the
# old one from different directories, plus a same-named file elsewhere whose
# link must stay.
set -euo pipefail

mkdir -p plugins/multi-agent/reference/routing plugins/multi-agent/skills/route docs/upstream

cat >plugins/multi-agent/reference/routing/rubric.md <<'MD'
# Routing rubric: when a role may run on Haiku

## The rule

No role routes to Haiku until it passes this repository's routing eval.
MD

cat >plugins/multi-agent/reference/defaults.yaml <<'YAML'
schema: 1
YAML

cat >plugins/multi-agent/README.md <<'MD'
# multi-agent

Role defaults live in [reference/defaults.yaml](reference/defaults.yaml). No role routes to Haiku
until it passes the routing eval; the [routing rubric](reference/routing-rubric.md) owns the rule.
MD

cat >plugins/multi-agent/reference/config.md <<'MD'
# Configuration

A layer may set any role to `haiku`; the resolver then adds a note pointing at the
[routing rubric](routing-rubric.md). The bundled layer is [defaults.yaml](defaults.yaml).
MD

cat >plugins/multi-agent/skills/route/SKILL.md <<'MD'
---
name: route
description: Resolve each role's model and effort.
---

# Route

A role that resolves to haiku gets a note; the rule is in
[the routing rubric](../../reference/routing-rubric.md#the-rule).
MD

cat >docs/upstream/haiku-5-5-launch.md <<'MD'
# Upstream source: Claude Haiku 5.5 launch

| Topic | Ours |
|---|---|
| H1 Routing | No role routes to `haiku` until it passes the routing eval: [routing rubric](../../plugins/multi-agent/reference/routing-rubric.md) |

This record replaces [the earlier routing record](routing-rubric.md).
MD

cat >docs/upstream/routing-rubric.md <<'MD'
# Earlier routing record

Replaced by haiku-5-5-launch.md.
MD
