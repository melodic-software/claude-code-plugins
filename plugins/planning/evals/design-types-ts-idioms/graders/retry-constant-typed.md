---
type: regex
pattern: '\bconst\s+\w+\s*:\s*(?:Readonly<\s*)?\w*Retry\w*|\}\s*(?:as\s+const\s+)?satisfies\s+(?:Readonly<\s*)?\w*Retry\w*'
flags: i
target: { source: file, path: .work/shipment-poller/design/type-inventory.md }
---
