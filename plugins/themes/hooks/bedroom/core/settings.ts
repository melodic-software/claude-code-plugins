import type { PluginOptions } from 'claude-code'

export const PHASES = ['dusk', 'evening', 'night', 'predawn', 'dawn', 'morning', 'noon', 'golden'] as const
export const WEATHERS = ['clear', 'overcast', 'rain', 'downpour', 'storm'] as const

type Spec =
  | { kind: 'choice'; options: readonly string[]; default: string }
  | { kind: 'time'; from: string; to: string; default: string }
  | { kind: 'boolean'; default: boolean }
  | { kind: 'string'; default: string }

/** The plugin's settings (`userConfig` in plugin.json), each with its range and default. */
export const SETTINGS = {
  time: { kind: 'choice', options: ['auto', ...PHASES], default: 'auto' },
  sunrise: { kind: 'time', from: '04:00', to: '09:00', default: 'auto' },
  sunset: { kind: 'time', from: '16:00', to: '22:00', default: 'auto' },
  weather: { kind: 'choice', options: ['auto', ...WEATHERS], default: 'auto' },
  lightning: { kind: 'choice', options: ['rare', 'normal', 'often'], default: 'normal' },
  sound: { kind: 'boolean', default: false },
  soundPlayer: { kind: 'string', default: '' },
  signal: { kind: 'boolean', default: true },
  hall: { kind: 'boolean', default: true },
  shader: { kind: 'boolean', default: true },
} as const satisfies Record<string, Spec>

export type SettingKey = keyof typeof SETTINGS
export type SettingValue<K extends SettingKey> = (typeof SETTINGS)[K]['default'] extends boolean ? boolean : string
/** The settings a command may hold an override for, in the store. */
export const OVERRIDES = ['time', 'weather', 'lightning', 'sound', 'signal', 'hall', 'shader'] as const
export type Override = (typeof OVERRIDES)[number]

let options: PluginOptions = {}
/** The options of this activation: a change to them reloads the module. */
export function useOptions(given: PluginOptions): void {
  options = given
}

function isValid(spec: Spec, value: unknown): boolean {
  if (spec.kind === 'boolean') return typeof value === 'boolean'
  if (typeof value !== 'string') return false
  if (spec.kind === 'choice') return spec.options.includes(value)
  if (spec.kind === 'time') return value === 'auto' || (/^\d\d:\d\d$/.test(value) && value >= spec.from && value <= spec.to && Number(value.slice(3)) < 60)
  return true
}

/** A setting's value now: the stored override, else the setting, else its default; one outside its range reads as the default. */
export function settingOf<K extends SettingKey>(key: K, stored: Partial<Record<Override, unknown>>): SettingValue<K> {
  const spec: Spec = SETTINGS[key]
  const held = (OVERRIDES as readonly string[]).includes(key) ? stored[key as Override] : undefined
  const value = isValid(spec, held) ? held : isValid(spec, options[key]) ? options[key] : spec.default
  return value as SettingValue<K>
}

/** Whether a word is a valid value of a setting a command may hold. */
export function accepts(key: Override, value: unknown): boolean {
  return isValid(SETTINGS[key], value)
}

/** HH:MM to minutes of the day. */
export function minutesOf(text: string): number {
  return Number(text.slice(0, 2)) * 60 + Number(text.slice(3, 5))
}
