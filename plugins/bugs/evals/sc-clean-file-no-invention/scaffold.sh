#!/usr/bin/env bash
# Seed the one file the scan targets.
set -euo pipefail

mkdir -p src
cat >src/calendar.js <<'JS'
// Gregorian calendar helpers. `year` is an integer.

// True when `year` is a Gregorian leap year.
export function isLeapYear(year) {
  return (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
}

// Days in February of `year`.
export function daysInFebruary(year) {
  return isLeapYear(year) ? 29 : 28;
}
JS
