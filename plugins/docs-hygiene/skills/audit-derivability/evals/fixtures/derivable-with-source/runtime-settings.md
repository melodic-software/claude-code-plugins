# Service runtime settings

The service listens on port `8080`. Its request timeout is `30` seconds and it
retries failed calls up to `3` times. The liveness probe is `/healthz` and the
readiness probe is `/readyz`. The log level is `info`.
