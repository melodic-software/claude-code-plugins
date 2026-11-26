export type Switch = { profile: string; phase: 'armed' | 'reloading'; off?: string[]; kind?: 'clear' | 'reset'; keeps?: string }

export type PickerEntry = { name: string; description: string }

declare module 'claude-code' {
  interface PluginState {
    'plugin-profiles': { switch: Switch | null; picker: PickerEntry[]; focused: string | null }
  }
}
