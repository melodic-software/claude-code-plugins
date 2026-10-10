#!/usr/bin/env bash
# Seeds a clinic shift-scheduling app whose pages all sit in one flat sidebar.
set -euo pipefail

mkdir -p docs src
cat > package.json <<'JSON'
{ "name": "crewroster", "private": true, "dependencies": { "react": "^19.0.0", "react-router-dom": "^7.0.0" } }
JSON
cat > docs/about.md <<'MD'
# Crewroster

Crewroster schedules nurses and medical assistants across a group of outpatient clinics.

Two kinds of users:
- Clinic managers build the schedule, approve shift swaps and time off, and run reports.
- Staff check their shifts, pick up open shifts, and request swaps or time off.

Every page sits in one flat sidebar, in the order the pages were built.
MD
cat > src/routes.tsx <<'TSX'
export const routes = [
  { path: '/dashboard', page: 'Dashboard' },
  { path: '/schedule/week', page: 'WeekSchedule' },
  { path: '/schedule/open-shifts', page: 'OpenShifts' },
  { path: '/swap-requests', page: 'SwapRequests' },
  { path: '/time-off', page: 'TimeOff' },
  { path: '/staff', page: 'StaffDirectory' },
  { path: '/staff/credentials', page: 'CredentialExpiry' },
  { path: '/reports/overtime', page: 'OvertimeReport' },
  { path: '/reports/coverage', page: 'CoverageReport' },
  { path: '/payroll-export', page: 'PayrollExport' },
  { path: '/announcements', page: 'Announcements' },
  { path: '/settings/locations', page: 'Locations' },
  { path: '/settings/shift-templates', page: 'ShiftTemplates' },
  { path: '/settings/integrations', page: 'Integrations' },
];
TSX
