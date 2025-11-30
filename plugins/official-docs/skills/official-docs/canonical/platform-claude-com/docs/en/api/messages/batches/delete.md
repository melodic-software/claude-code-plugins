---
source_url: https://platform.claude.com/docs/en/api/messages/batches/delete
source_type: sitemap
content_hash: sha256:85e37d83a48a23d0ecf86ad64aa557fd09f94a87d895c9874f21d07803d54cbd
sitemap_url: https://docs.claude.com/sitemap.xml
fetch_method: markdown
---

## Delete

**delete** `/v1/messages/batches/{message_batch_id}`

Delete a Message Batch.

Message Batches can only be deleted once they've finished processing. If you'd like to delete an in-progress batch, you must first cancel it.

Learn more about the Message Batches API in our [user guide](https://docs.claude.com/en/docs/build-with-claude/batch-processing)

### Path Parameters

- `message_batch_id: string`

  ID of the Message Batch.

### Returns

- `DeletedMessageBatch = object { id, type }`

  - `id: string`

    ID of the Message Batch.

  - `type: "message_batch_deleted"`

    Deleted object type.

    For Message Batches, this is always `"message_batch_deleted"`.

    - `"message_batch_deleted"`

### Example

```http
curl https://api.anthropic.com/v1/messages/batches/$MESSAGE_BATCH_ID \
    -X DELETE \
    -H "X-Api-Key: $ANTHROPIC_API_KEY"
```
