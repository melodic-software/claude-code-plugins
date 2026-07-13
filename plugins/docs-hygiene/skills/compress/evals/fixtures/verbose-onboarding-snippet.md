# Onboarding: local build

Basically, before you really get started, you should just make sure that you have
the required toolchain installed. Honestly, this is perhaps the single most common
thing that trips new contributors up, so it is really worth double-checking.

Run the build. The build MUST complete with zero warnings — warnings are treated as
errors and will block the merge. If you happen to see any warnings at all, you will
want to fix the root cause rather than suppressing them.

Set `MAX_UPLOAD_MB=25` before starting the dev server; uploads above 25 MB are
rejected by the gateway.
