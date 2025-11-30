<!-- Source: https://docs.claude.com/en/api/files-delete -->

# Delete a File

DELETE /v1/files/{file_id}
Make a file inaccessible through the API

The Files API allows you to upload and manage files to use with the Claude API without having to re-upload content with each request. For more information about the Files API, see the [developer guide for files](/en/docs/build-with-claude/files).

<Note>
  The Files API is currently in beta. To use the Files API, you'll need to include the beta feature header: `anthropic-beta: files-api-2025-04-14`.

  Please reach out through our [feedback form](https://forms.gle/tisHyierGwgN4DUE9) to share your experience with the Files API.
</Note>