# Harbor documentation: sandboxing

Synthetic source page for the attribution golden set. Harbor is a fictional developer sandbox
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/harbor/docs/sandboxing`.

## Set up Ridge

Harbor's sandbox runs on Ridge virtual machines with the relay helper installed.

Ridge passes any start of a host program, for example a binary under `/host/bin/`, across to the
host through a relay socket. That socket is closed only by the sandbox's optional syscall filter.
If the filter is absent, or `allowRelaySockets` is on, the socket remains open.

To install the filter, run `harbor sandbox add-filter` once per machine.

## Platform support

Harbor's sandbox supports Ridge 2 and later.
