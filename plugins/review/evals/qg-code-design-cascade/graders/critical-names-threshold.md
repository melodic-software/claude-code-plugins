---
type: regex
pattern: '(?:^|\n)[ \t>]*(?:(?:[-*+]|\d+[.)])[ \t]+)?(?:#+[ \t]+)?\**CRITICAL\b(?![ \t]*\**[ \t]*\d)[^\n]*(?:FREE_SHIPPING_THRESHOLD|(?<![:\d])\b50\b)|(?:\|[ \t]*\**CRITICAL\**[ \t]*\||[(\[][ \t]*\**CRITICAL\**[ \t]*[)\]]|\bSeverity\**[ \t]*[:=][ \t]*\**CRITICAL\b|\b(?:is|are)[ \t]+\**CRITICAL\b|(?<!not )\brated[ \t]+(?:as[ \t]+)?\**CRITICAL\b)[^\n]*(?:FREE_SHIPPING_THRESHOLD|(?<![:\d])\b50\b)|(?:FREE_SHIPPING_THRESHOLD|(?<![:\d])\b50\b)[^\n]*(?:\|[ \t]*\**CRITICAL\**[ \t]*\||[(\[][ \t]*\**CRITICAL\**[ \t]*[)\]]|\bSeverity\**[ \t]*[:=][ \t]*\**CRITICAL\b|\b(?:is|are)[ \t]+\**CRITICAL\b|(?<!not )\brated[ \t]+(?:as[ \t]+)?\**CRITICAL\b)'
---
