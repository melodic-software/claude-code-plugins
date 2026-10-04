# Apps: desktop and mobile

`principles.md` applies first. A native or cross-platform app inherits a platform's design language
before it inherits a brand, so read the project, then the platform.

## Read the project first

- The app's theme, tokens and asset catalogs; the component or widget library in use (SwiftUI,
  Jetpack Compose, WinUI, Flutter, React Native, Electron with a web stack).
- Existing screens closest to the one being designed, and any design-system doc.

## Follow the platform

- Use the platform's controls, navigation patterns and system fonts unless the project has replaced
  them deliberately.
- Honor the system settings the user chose: light or dark appearance, text size, reduced motion,
  high contrast.
- Touch targets and spacing follow the platform guideline for the device.
- An Electron or web-stack app follows `web.md` for its content and the host platform for its
  window chrome, menus and shortcuts.

- **Pointer**: Apple Human Interface Guidelines, <https://developer.apple.com/design/human-interface-guidelines>;
  Material 3, <https://m3.material.io/>; Fluent 2, <https://fluent2.microsoft.design/>
- **As of**: 2026-10-04
- **Recheck trigger**: a platform publishes a new major version of its guidelines.

## Route

Take each concern to the highest-ranked installed and reachable route. Apple-platform tooling is
Mac-only and marked deferred in the routing data until it is tested; without it, answer from the
platform guidelines above.
