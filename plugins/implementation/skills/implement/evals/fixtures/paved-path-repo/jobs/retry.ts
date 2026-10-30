export function withRetry(run: () => Promise<void>, attempts = 3): () => Promise<void> {
  return async () => {
    for (let attempt = 1; ; attempt++) {
      try {
        return await run();
      } catch (error) {
        if (attempt >= attempts) throw error;
      }
    }
  };
}
