<!-- Source: https://docs.claude.com/en/api/deleting-message-batches -->

# Delete a Message Batch

delete /v1/messages/batches/{message_batch_id}
Delete a Message Batch.

Message Batches can only be deleted once they've finished processing. If you'd like to delete an in-progress batch, you must first cancel it.

Learn more about the Message Batches API in our [user guide](/en/docs/build-with-claude/batch-processing)