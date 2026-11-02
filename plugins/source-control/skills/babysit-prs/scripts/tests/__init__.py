import os

# The verdict reader's index mode turns on when its legacy FAILs file sits
# beside it (babysit_verify_evidence.LEGACY_FAILS_FILE); these suites fake the
# whole listing, so they read none unless a test names one.
os.environ.setdefault("BABYSIT_VERIFY_LEGACY_FAILS", "")
