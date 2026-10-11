declare module 'claude-code' {
  // A missing or false value means masked (fail closed).
  interface PluginState {
    'display-redaction': { disabled?: boolean }
  }
}
