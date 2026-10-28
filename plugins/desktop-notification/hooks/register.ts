import type { Register } from 'claude-code'

// The title the Notification settings hook keys on: it acts on a plugin_notification with this title only.
const TITLE = 'desktop-notification'

// Forwards every toast any mod raises to a native notification, then lets the toast show.
export const register: Register = (on, options) => {
  if (options.desktop_notification_enabled === false || options.desktop_notification_forward_toasts_enabled === false) return
  // With every channel off the settings hook sends nothing, so $.ui.notify would be the only alert.
  const channels = ['bell', 'terminal_notify', 'os_toast'].map(c => options[`desktop_notification_${c}_enabled`])
  if (channels.every(v => v === false)) return
  on('ui.toast', ($, e, next) => {
    $.ui.notify(e.text, { title: TITLE }).catch(() => undefined)
    return next(e)
  })
}
