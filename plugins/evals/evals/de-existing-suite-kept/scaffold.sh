#!/usr/bin/env bash
# Seed a support bot that calls OpenAI and last quarter's three-case suite.
set -euo pipefail

mkdir -p bot evals/support-bot

cat >bot/reply.py <<'PY'
from openai import OpenAI

client = OpenAI()


def draft_reply(ticket: str) -> str:
    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[
            {"role": "system", "content": "You answer customer support tickets for an outdoor gear shop."},
            {"role": "user", "content": ticket},
        ],
    )
    return response.choices[0].message.content
PY

cat >evals/support-bot/cases.jsonl <<'JSONL'
{"id": "refund-window", "input": "Can I return hiking boots I bought 40 days ago?", "expected": "Explains the 30-day return window and offers store credit"}
{"id": "password-reset-loop", "input": "The reset link keeps sending me back to the login page.", "expected": "Suggests clearing cookies and gives the support form link"}
{"id": "po-box-shipping", "input": "Do you ship tents to a PO box?", "expected": "Says tents ship to street addresses only"}
JSONL
