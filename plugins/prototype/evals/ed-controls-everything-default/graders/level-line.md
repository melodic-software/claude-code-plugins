---
type: regex
target: trace
arm: with-only
pattern: '^(?:(?!"name":"(?:Write|Edit)")[\s\S])*?"type":"assistant","message":\{(?:(?!"name":"(?:Write|Edit)")[^\n])*?"type":"text","text":"(?:[^"\\\n]|\\.)*?level: standard \(default(?:\)|; resolver unavailable: (?!<))'
---
