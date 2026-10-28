# Start a timer

A user starts tracking time against a project and sees the elapsed time grow.

## Parts

- start: a new timer begins at 00:00 for the chosen project
- resume: a timer survives a page reload

## Entry points

- the `Start` button on the dashboard
- pressing `t` anywhere on the dashboard

## Drive

Start from an empty scratch database with the project `Website refresh`.

- Choose `Start` in the row named `Website refresh`; the row shows a running clock within two seconds.
- Reload the page; the same clock is still running and has not reset.

## Traps

- A timer left running from an earlier run makes `start` look like a switch; reset the database first.
