Closes #12

<!-- reviewer-media:start -->
## Reviewer media

For reviewers: a narrated walkthrough of this change. Watch it before the diff.

<!-- reviewer-media:posted 1111111111111111111111111111111111111111 -->

https://example.com/user-attachments/assets/video.mp4

<details>
<summary>Contact sheet</summary>

![Contact sheet 1](https://example.com/user-attachments/assets/sheet-1.png)

</details>

<details>
<summary>Chapters</summary>

- 0:00 What changed
- 0:42 The retry path

</details>
<!-- reviewer-media:end -->

## Summary

Adds a retry to the upload step.

## Fix

The upload call retries once on a timeout.

## Verification

- `bash scripts/upload.test.sh` exits 0.

## Related

- None.
