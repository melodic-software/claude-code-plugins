# Release checklist

**Tag before you publish.** Tag before you publish, because the release job reads the
version from the tag and an untagged publish really just ships as version 0.0.0.

**Never reuse a version number.** As the rule name says, a version number is never
reused: the registry basically rejects a second upload under the same number.
