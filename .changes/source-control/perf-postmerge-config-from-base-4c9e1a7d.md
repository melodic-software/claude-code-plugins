---
bump: patch
---

### Changed

- The post-merge check reads default-branch files (the tracker binding, the pipeline config) from the checkout `BABYSIT_CONFIG_CHECKOUT` names when its HEAD is main's tip the workflow step passed in `MAIN_TIP_SHA`, and through the contents API otherwise.
