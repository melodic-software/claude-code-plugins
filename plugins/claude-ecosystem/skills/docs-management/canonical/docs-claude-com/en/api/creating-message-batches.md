<!-- Source: https://docs.claude.com/en/api/creating-message-batches -->

# Create a Message Batch

post /v1/messages/batches
Send a batch of Message creation requests.

The Message Batches API can be used to process multiple Messages API requests at once. Once a Message Batch is created, it begins processing immediately. Batches can take up to 24 hours to complete.

Learn more about the Message Batches API in our [user guide](/en/docs/build-with-claude/batch-processing)

## Feature Support

The Message Batches API supports all active models. All features available in the Messages API, including beta features, are available through the Message Batches API.

Batches may contain up to 100,000 requests and be up to 256 MB in total size.