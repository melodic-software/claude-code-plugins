declare module 'claude-code' {
  // A missing value means masked (fail closed).
  interface PluginState {
    'display-redaction': { disabled?: true }
  }
}
