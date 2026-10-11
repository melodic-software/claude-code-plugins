export type LiveMode = 'pane' | 'band' | 'off'
// kind and color come from the breakdown row; branch on kind, never on name.
export type LiveCategory = { name: string; tokens: number; percent: number; kind: string; color: string; deferred: boolean }
export type LiveView = { used: number; window: number; compactsAt?: number; percent: number; categories: LiveCategory[] }

declare module 'claude-code' {
  interface PluginState {
    // Seeded with ifVersion: 0 so a hot reload keeps session choices; pane open/closed comes from $.ui.panes(), not state.
    'context-budget': { mode: LiveMode; view: LiveView | null; error: string | null }
  }
}
