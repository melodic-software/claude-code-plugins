# Retry helper

In order to retry a failed request, the helper doubles its wait between
attempts and gives up after five tries.

The helper plays a crucial role in keeping the queue drained during an outage.

I hope this helps — the defaults live in `config.toml` if you want to change
them.
