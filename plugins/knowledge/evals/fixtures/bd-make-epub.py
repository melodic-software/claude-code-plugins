"""Write a two-chapter EPUB to argv[1]; with --traversal, add a ../evil.txt entry."""

import sys
import zipfile

CONTAINER = """<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""

PACKAGE = """<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="id">field-notes-on-retries</dc:identifier>
    <dc:title>Field Notes on Retries</dc:title>
    <dc:creator>A. Author</dc:creator>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>
"""

NAV = """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<body><nav epub:type="toc"><ol>
  <li><a href="ch1.xhtml">Chapter 1. Backoff</a></li>
  <li><a href="ch2.xhtml">Chapter 2. Idempotency</a></li>
</ol></nav></body></html>
"""

CHAPTER = """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><body>
<h1>{title}</h1>
<p>{body}</p>
</body></html>
"""

CHAPTERS = {
    "ch1.xhtml": (
        "Chapter 1. Backoff",
        "Retry with exponential backoff and full jitter, so many clients do not retry in lockstep.",
    ),
    "ch2.xhtml": (
        "Chapter 2. Idempotency",
        "A retried request is safe only when the operation is idempotent; give each one a key.",
    ),
}


def main():
    out = sys.argv[1]
    with zipfile.ZipFile(out, "w") as book:
        book.writestr(
            zipfile.ZipInfo("mimetype"), "application/epub+zip", zipfile.ZIP_STORED
        )
        book.writestr("META-INF/container.xml", CONTAINER)
        book.writestr("OEBPS/content.opf", PACKAGE)
        book.writestr("OEBPS/nav.xhtml", NAV)
        for name, (title, body) in CHAPTERS.items():
            book.writestr("OEBPS/" + name, CHAPTER.format(title=title, body=body))
        if "--traversal" in sys.argv[2:]:
            book.writestr("../evil.txt", "planted outside the cache\n")


if __name__ == "__main__":
    main()
