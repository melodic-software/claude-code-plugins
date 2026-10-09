---
type: regex
pattern: 'playwright-cli\s+(?:-s|--session)[= ]["'']?([\w.-]+)["'']?\s+open\b[\s\S]*?playwright-cli\s+(?:-s|--session)[= ]["'']?\1["'']?\s+(?:--\S+\s+)*(?:snapshot|find)\b[\s\S]*?playwright-cli\s+(?:-s|--session)[= ]["'']?\1["'']?\s+(?:--\S+\s+)*click\b[\s\S]*playwright-cli\s+(?:-s|--session)[= ]["'']?\1["'']?\s+close\b'
---
