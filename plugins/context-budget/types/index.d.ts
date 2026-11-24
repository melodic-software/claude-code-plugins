export type LiveMode = 'pane' | 'band' | 'off'
export type LiveCategory = { name: string; tokens: number; percent: number; kind: string; color: string; deferred: boolean }
export type LiveView = { used: number; window: number; compactsAt?: number; percent: number; categories: LiveCategory[] }
export type LiveState = { view: LiveView | null; error: string | null }

declare module 'claude-code' {
  interface PluginState {
    'context-budget': { mode: LiveMode; live: LiveState }
  }
}
