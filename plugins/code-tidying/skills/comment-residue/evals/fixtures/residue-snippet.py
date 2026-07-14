def flush_buffer(items):
    # used to batch writes here; now flushes each item immediately
    for item in items:
        write(item)  # as you asked, keep the order stable


def parse(tokens):
    # Task 2 replaces the old recursive-descent parser
    # see PR #45 for the original design discussion
    return _parse(tokens)


def checksum(payload):
    # Sums the payload bytes modulo 2**32.
    # TODO(#123): switch to CRC32 once the format is frozen
    return sum(payload) % (2**32)
