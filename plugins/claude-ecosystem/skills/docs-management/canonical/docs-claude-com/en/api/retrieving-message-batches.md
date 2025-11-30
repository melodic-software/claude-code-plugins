<!-- Source: https://docs.claude.com/en/api/retrieving-message-batches -->

# Retrieve a Message Batch

get /v1/messages/batches/{message_batch_id}
This endpoint is idempotent and can be used to poll for Message Batch completion. To access the results of a Message Batch, make a request to the `results_url` field in the response.

Learn more about the Message Batches API in our [user guide](/en/docs/build-with-claude/batch-processing)