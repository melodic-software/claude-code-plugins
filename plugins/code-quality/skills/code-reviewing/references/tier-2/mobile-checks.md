# Mobile Patterns - Tier 2

Comprehensive mobile-specific code review checks for iOS (Swift/UIKit/SwiftUI), Android (Kotlin/Jetpack Compose), and Flutter/Dart applications.

**When to Load:** Reviewing `.swift`, `.kt`, `.dart`, `.m`, `.mm` files.

## 1. iOS Specific Patterns (Swift/UIKit/SwiftUI)

### Swift Language Patterns

- [ ] **Optional unwrapping safety** - Use `if let`, `guard let`, or nil coalescing over force unwrapping (`!`)
- [ ] **Value types preferred** - Use `struct` over `class` when inheritance isn't needed (safer concurrency)
- [ ] **Protocol-oriented design** - Prefer protocols and extensions over deep inheritance hierarchies
- [ ] **Weak references for delegates** - Delegate properties marked `weak` to prevent retain cycles
- [ ] **Capture lists in closures** - Use `[weak self]` or `[unowned self]` appropriately to avoid retain cycles
- [ ] **SwiftUI state management** - Use `@State`, `@Binding`, `@ObservedObject`, `@StateObject` correctly
- [ ] **Combine framework** - Properly manage publisher subscriptions with `store(in:)` or `assign(to:)`

### Memory Management

- [ ] **Retain cycles detected** - Check for strong reference cycles between objects (especially in closures)
- [ ] **Image caching** - Large images cached and released appropriately to avoid memory pressure
- [ ] **View controller lifecycle** - Cleanup in `deinit` and `viewDidDisappear` when needed
- [ ] **Autoreleasepool usage** - Wrap tight loops creating many temporary objects in `autoreleasepool`

### UIKit/SwiftUI Patterns

- [ ] **Main thread UI updates** - All UI updates wrapped in `DispatchQueue.main.async` when on background thread
- [ ] **SwiftUI view performance** - Avoid expensive computation in view body; use computed properties or view models
- [ ] **Reusable cells** - Table/collection view cells properly reused with `dequeueReusableCell`
- [ ] **Storyboard/XIB constraints** - Auto Layout constraints properly configured without conflicts

## 2. Android Specific Patterns (Kotlin/Jetpack Compose)

### Kotlin Language Patterns

- [ ] **Null safety** - Use nullable types (`?`) and safe calls (`?.`) instead of `!!` force unwrapping
- [ ] **Coroutines over callbacks** - Prefer coroutines for async operations over nested callbacks
- [ ] **Data classes** - Use `data class` for model objects to get `equals()`, `hashCode()`, `copy()` for free
- [ ] **Sealed classes for state** - Use `sealed class` for finite state machines and result types
- [ ] **Extension functions** - Appropriate use of extension functions for utility methods
- [ ] **Scope functions** - Proper use of `let`, `run`, `with`, `apply`, `also` (not overused)

### Android Lifecycle

- [ ] **Lifecycle awareness** - Activities/Fragments properly handle lifecycle events (onCreate, onPause, etc.)
- [ ] **ViewModel usage** - UI state managed in ViewModel, survives configuration changes
- [ ] **LiveData/StateFlow** - Observe lifecycle-aware data streams to avoid memory leaks
- [ ] **Coroutine scope management** - Use `viewModelScope` or `lifecycleScope` for automatic cancellation

### Jetpack Compose

- [ ] **Composable stability** - Composables properly annotated with `@Stable` or `@Immutable` when needed
- [ ] **Recomposition optimization** - Avoid unnecessary recompositions with `remember`, `derivedStateOf`
- [ ] **Side effects** - Use `LaunchedEffect`, `DisposableEffect`, `SideEffect` appropriately
- [ ] **State hoisting** - State lifted to appropriate level, unidirectional data flow maintained

## 3. Flutter/Dart Patterns

### Dart Language Patterns

- [ ] **Null safety** - Proper use of nullable types (`?`) and null-aware operators (`??`, `?.`, `!`)
- [ ] **Async/await** - Asynchronous operations use `async`/`await` instead of raw `Future` chaining
- [ ] **Const constructors** - Use `const` constructors where possible for compile-time constants
- [ ] **Immutability** - Prefer `final` fields over mutable state when possible

### Flutter Widget Patterns

- [ ] **StatelessWidget vs StatefulWidget** - Correct widget type chosen based on mutability needs
- [ ] **Widget composition** - Complex widgets broken into smaller, reusable components
- [ ] **BuildContext usage** - BuildContext not stored; accessed only within build methods
- [ ] **Keys usage** - Keys used appropriately for list items and stateful widgets that move

### State Management

- [ ] **State management pattern** - Consistent use of chosen pattern (Provider, Riverpod, Bloc, GetX, etc.)
- [ ] **Provider scoping** - Providers scoped appropriately in widget tree
- [ ] **Stream/Future disposal** - Streams and futures properly disposed to avoid memory leaks

## 4. Battery Optimization

- [ ] **Location usage** - Use lowest accuracy location service needed; stop when not in use
- [ ] **Background execution** - Minimize background work; use WorkManager (Android) or Background Tasks (iOS)
- [ ] **Wake locks avoided** - Wake locks released promptly; use partial wake locks when possible
- [ ] **Sensor polling** - Sensors (accelerometer, gyroscope) sampled at lowest frequency needed
- [ ] **Network batching** - Network requests batched to reduce radio wake-ups
- [ ] **Animation efficiency** - Animations paused when app in background

## 5. Memory Management

- [ ] **Large object cleanup** - Bitmaps, media files, large buffers released when no longer needed
- [ ] **Cache size limits** - In-memory caches have size limits and eviction policies
- [ ] **Memory leaks** - Listeners, callbacks, observers properly unregistered
- [ ] **Pagination** - Large data sets loaded incrementally (pagination, lazy loading)
- [ ] **Image loading** - Use efficient image loading libraries (Glide, Coil, Kingfisher, cached_network_image)
- [ ] **Native memory** - Native code properly releases allocated memory

## 6. Network Efficiency

- [ ] **Request batching** - Multiple small requests consolidated when possible
- [ ] **Response caching** - HTTP responses cached appropriately with cache headers
- [ ] **Compression** - Request/response bodies compressed (gzip, Brotli)
- [ ] **Connection reuse** - HTTP connection pooling enabled
- [ ] **Timeouts configured** - Appropriate timeouts for connect, read, write operations
- [ ] **Retry logic** - Exponential backoff for retries; circuit breaker pattern for failing services
- [ ] **Bandwidth awareness** - Large downloads deferred on metered connections

## 7. Offline-First Architecture

- [ ] **Local-first data** - App functional with cached data when offline
- [ ] **Sync strategy** - Clear strategy for syncing local changes to server
- [ ] **Conflict resolution** - Mechanism for resolving sync conflicts (last-write-wins, CRDT, etc.)
- [ ] **Queue for offline actions** - User actions queued when offline, executed when online
- [ ] **Network state monitoring** - App monitors network state and adapts behavior
- [ ] **Optimistic updates** - UI updated immediately with local changes, synced in background

## 8. Local Storage and Caching

- [ ] **Storage choice** - Appropriate storage mechanism chosen (SharedPreferences, SQLite, Realm, CoreData, etc.)
- [ ] **Encryption** - Sensitive data encrypted at rest (Keychain, EncryptedSharedPreferences)
- [ ] **Storage limits** - App respects storage quotas; handles low storage conditions
- [ ] **Cache invalidation** - Stale cache data invalidated or refreshed appropriately
- [ ] **Database migrations** - Schema migrations handled correctly for database upgrades
- [ ] **File storage cleanup** - Temporary files and old cache cleaned up periodically

## 9. Push Notifications

- [ ] **Notification permissions** - Request permissions at appropriate time with clear rationale
- [ ] **Notification channels** - Android notification channels properly configured
- [ ] **Deep linking** - Notifications open relevant screen in app with proper context
- [ ] **Token management** - Push notification tokens refreshed and synced to server
- [ ] **Notification grouping** - Related notifications grouped appropriately
- [ ] **Quiet hours respected** - App respects system Do Not Disturb settings

## 10. Deep Linking

- [ ] **URL scheme validation** - Custom URL schemes validated to prevent injection attacks
- [ ] **Universal Links / App Links** - iOS Universal Links or Android App Links configured
- [ ] **Navigation state** - Deep links restore proper navigation stack, not just single screen
- [ ] **Authentication required** - Deep links to protected content enforce authentication
- [ ] **Fallback handling** - Graceful fallback when deep link target doesn't exist

## 11. App Lifecycle Handling

- [ ] **Foreground/background transitions** - App properly handles foreground/background transitions
- [ ] **State restoration** - User's place in app restored after process death (Android) or backgrounding
- [ ] **Resource release** - Heavy resources (camera, audio) released when app backgrounded
- [ ] **Configuration changes** - Android configuration changes (rotation, theme) handled gracefully
- [ ] **Scene lifecycle (iOS)** - iOS multi-window support with proper scene lifecycle handling

## 12. Permissions Handling

- [ ] **Runtime permissions** - Permissions requested at runtime, not just manifest/Info.plist
- [ ] **Permission rationale** - Clear explanation provided before requesting sensitive permissions
- [ ] **Graceful degradation** - App remains functional when optional permissions denied
- [ ] **Permission revocation** - App handles permissions being revoked after initial grant
- [ ] **Minimal permissions** - Only necessary permissions requested
- [ ] **Permission scoping** - Request least-privileged permission level (e.g., approximate vs precise location)

## 13. Responsive Layouts

- [ ] **Multiple screen sizes** - Layout adapts to phone, tablet, foldable form factors
- [ ] **Orientation support** - Portrait and landscape orientations supported appropriately
- [ ] **Safe area insets** - UI respects safe area insets (notches, home indicator)
- [ ] **Dynamic type** - Text scales with user's font size preference
- [ ] **Constraint-based layout** - Auto Layout (iOS) or ConstraintLayout (Android) used for flexible UI
- [ ] **Responsive breakpoints** - Different layouts for compact, medium, expanded widths

## 14. Accessibility for Mobile

- [ ] **Screen reader support** - All interactive elements have accessibility labels
- [ ] **Semantic meaning** - Use semantic HTML/widgets (buttons vs clickable divs)
- [ ] **Touch target size** - Minimum 44x44pt (iOS) or 48x48dp (Android) touch targets
- [ ] **Color contrast** - WCAG AA contrast ratios met (4.5:1 text, 3:1 UI components)
- [ ] **Keyboard navigation** - App navigable with external keyboard on tablets
- [ ] **Dynamic type** - UI adapts to user's text size preferences without breaking
- [ ] **VoiceOver/TalkBack** - Proper focus order and announcements for screen readers
- [ ] **Reduced motion** - Respect system preference for reduced motion
- [ ] **Accessibility traits** - Proper traits/roles assigned (button, header, link, etc.)

## 15. Platform-Specific Best Practices

### iOS

- [ ] **Background app refresh** - Use Background App Refresh API appropriately
- [ ] **Handoff support** - Consider Handoff for cross-device continuity
- [ ] **SiriKit integration** - Add Siri shortcuts for common actions when appropriate
- [ ] **Dark mode support** - UI adapts to system dark mode setting
- [ ] **Haptic feedback** - Use haptic feedback appropriately for tactile responses

### Android

- [ ] **Material Design** - Follow Material Design guidelines for UI components
- [ ] **Adaptive icons** - App icon supports adaptive icon format
- [ ] **Scoped storage** - Use Scoped Storage APIs for Android 10+
- [ ] **Edge-to-edge display** - Support edge-to-edge display with proper insets
- [ ] **Picture-in-Picture** - PiP mode implemented for video playback when appropriate

### Flutter

- [ ] **Platform channels** - Native platform code accessed via platform channels
- [ ] **Plugins used** - Prefer well-maintained official or community plugins
- [ ] **Hot reload friendly** - Code structured to support hot reload during development
- [ ] **Build variants** - Separate configurations for dev, staging, production

## Notes

These checks complement the universal code review principles in the main SKILL.md. When reviewing mobile code, combine these mobile-specific checks with general code quality, security, and performance checks.

**Last Updated:** 2025-11-28
