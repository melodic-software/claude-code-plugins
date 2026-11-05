"""Write a two-page text PDF to argv[1]: a chapter on backoff and one on idempotency."""

import sys

PAGES = [
    [
        "Field Notes on Retries",
        "Chapter 1. Backoff",
        "Retry with exponential backoff and full jitter, so many clients do not retry in lockstep.",
        "Start at 100 ms, double each attempt, cap the delay at 30 seconds, stop after 6 attempts.",
    ],
    [
        "Chapter 2. Idempotency",
        "A retried request is safe only when the operation is idempotent.",
        "The client sends an Idempotency-Key header, a UUID it generates once per logical operation.",
        "The server stores the key with the first response for 24 hours.",
        "A replay of a completed key returns the stored response with no new side effect.",
        "A replay that arrives while the first request is still in flight gets 409 Conflict.",
        "A key reused with a different request body gets 422 Unprocessable Content.",
    ],
]


def esc(text):
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def stream(lines):
    body = ["BT", "/F1 11 Tf", "14 TL", "72 740 Td"]
    for line in lines:
        body.append("(" + esc(line) + ") Tj T*")
    body.append("ET")
    return "\n".join(body).encode("latin-1")


def main():
    n = len(PAGES)
    objs = []
    kids = " ".join(f"{3 + 2 * i} 0 R" for i in range(n))
    objs.append(b"<< /Type /Catalog /Pages 2 0 R >>")
    objs.append(f"<< /Type /Pages /Kids [{kids}] /Count {n} >>".encode())
    font = 3 + 2 * n
    for i, lines in enumerate(PAGES):
        content = 4 + 2 * i
        objs.append(
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
            f"/Resources << /Font << /F1 {font} 0 R >> >> /Contents {content} 0 R >>".encode()
        )
        data = stream(lines)
        objs.append(b"<< /Length %d >>\nstream\n" % len(data) + data + b"\nendstream")
    objs.append(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")

    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for num, obj in enumerate(objs, start=1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % num + obj + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
    for off in offsets:
        out += b"%010d 00000 n \n" % off
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (
        len(objs) + 1,
        xref,
    )
    with open(sys.argv[1], "wb") as fh:
        fh.write(out)


if __name__ == "__main__":
    main()
