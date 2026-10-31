# Exporter 2.4

This pivotal release delves into export speed. The exporter now leverages a streaming
writer that sends each row as soon as it is read, so a 2 GB table no longer has to fit in
memory. Additionally, the CLI showcases a new `--dry-run` flag that prints the row count
without writing a file.

The future looks bright for the exporter. I hope this helps!
