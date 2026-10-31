export type LiveMode = 'pane' | 'band' | 'off'
// kind and color come from the breakdown row; branch on kind, not name, except the Skills warning
// in hooks/parts.tsx, which no kind tells apart. color is a theme key.
export type LiveCategory = { name: string; tokens: number; percent: number; kind: string; color: string; deferred: boolean }
export type LiveView = { used: number; window: number; compactsAt?: number; percent: number; categories: LiveCategory[] }
// One value so a refresh writes view and error together. Both null: no response measured yet.
export type LiveState = { view: LiveView | null; error: string | null }

declare module 'claude-code' {
  interface PluginState {
    // mode reads the live_display option until /context-budget live sets it; a hot reload keeps that
    // write. Pane open or closed comes from $.ui.panes(), not state.
    'context-budget': { mode: LiveMode; live: LiveState }
  }
}
