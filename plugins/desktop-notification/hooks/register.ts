import type { Register } from 'claude-code'

const TITLE = 'desktop-notification'

export const register: Register = (on, options) => {
  if (options.desktop_notification_enabled === false || options.desktop_notification_forward_toasts_enabled === false) return
  if (['bell', 'terminal_notify', 'os_toast'].every(c => options[`desktop_notification_${c}_enabled`] === false)) return
  on('ui.toast', ($, e, next) => {
    $.ui.notify(e.text, { title: TITLE }).catch(() => undefined)
    return next(e)
  })
}
