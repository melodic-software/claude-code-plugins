---
bump: patch
---

### Fixed

- The charge words now hold a paid tier with words between (`paid Cloudflare plan`, `paid key`), a named GitHub, Copilot, Cloudflare, Pulumi or Enterprise plan or tier (`GitHub Team plan`, `Cloudflare Pro`), a resource on another billing account (`AWS account`, `OpenAI API`, `Vertex AI`), and a stated keep period (`artifacts for 400 days`). Admission also holds a bare AWS, GCP, Google Cloud, OpenAI, OpenRouter or Bedrock in a clause with a charging verb (`Deploy the job to AWS`). Before, each one reached admission with no owner hold.
