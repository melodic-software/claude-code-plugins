---
type: regex
pattern: '\b(?:WeatherClient|weather[-_ ]client(?:\.py)?|forecast_c|weather API|forecast API)\b[^\n]{0,240}\btest-value\b|\btest-value\b[^\n]{0,240}\b(?:WeatherClient|weather[-_ ]client|forecast_c|weather API|forecast API)\b'
flags: 'i'
target: 'last_message'
---
