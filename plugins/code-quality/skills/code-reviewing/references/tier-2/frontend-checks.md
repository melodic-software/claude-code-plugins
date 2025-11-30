# Frontend-Specific Code Review Checks

## Accessibility (WCAG 2.1 AA) - Expanded

- [ ] **Semantic HTML** - Use semantic elements (`<nav>`, `<main>`, `<article>`, `<section>`, `<aside>`, `<header>`, `<footer>`) instead of generic `<div>` where appropriate
- [ ] **ARIA labels** - All interactive elements have accessible names via `aria-label`, `aria-labelledby`, or visible text
- [ ] **ARIA roles** - Use ARIA roles correctly and only when semantic HTML is insufficient (prefer semantic HTML first)
- [ ] **ARIA states** - Dynamic state changes are announced (`aria-expanded`, `aria-selected`, `aria-pressed`, `aria-checked`, `aria-disabled`)
- [ ] **Keyboard navigation** - All interactive elements are keyboard accessible (Tab, Enter, Space, Arrow keys where appropriate)
- [ ] **Focus management** - Focus order is logical; focus is visible; focus is trapped in modals; focus is restored after dialogs close
- [ ] **Focus indicators** - Custom focus styles meet 3:1 contrast ratio and are not removed without replacement
- [ ] **Alt text** - Images have descriptive alt text; decorative images have `alt=""` or `role="presentation"`
- [ ] **Color contrast** - Text meets 4.5:1 (normal text) or 3:1 (large text 18pt+) contrast ratio against background
- [ ] **Color not sole indicator** - Information is not conveyed by color alone (use icons, text, patterns)
- [ ] **Form labels** - All form inputs have associated `<label>` elements or `aria-label`
- [ ] **Form errors** - Error messages are associated with inputs via `aria-describedby` or `aria-errormessage`
- [ ] **Required fields** - Marked with `required` attribute or `aria-required="true"` and visually indicated
- [ ] **Landmark regions** - Page has proper landmark structure (`role="main"`, `role="navigation"`, `role="complementary"`, etc.)
- [ ] **Heading hierarchy** - Headings follow logical order (h1 → h2 → h3, no skipped levels)
- [ ] **Link purpose** - Link text describes destination ("Read more about accessibility" vs "Click here")
- [ ] **Skip links** - "Skip to main content" link provided for keyboard users
- [ ] **Live regions** - Dynamic content updates use `aria-live`, `aria-atomic`, `role="status"`, `role="alert"` appropriately
- [ ] **Screen reader testing** - Tested with at least one screen reader (NVDA, JAWS, VoiceOver, TalkBack)

## Internationalization (i18n) - Expanded

- [ ] **Externalized strings** - All user-facing text uses i18n system (no hardcoded strings in components)
- [ ] **Translation keys** - Keys are namespaced and descriptive (`auth.login.submitButton` vs `button1`)
- [ ] **Pluralization** - Handles plural forms correctly for all supported locales (some languages have 6+ plural forms)
- [ ] **Number formatting** - Uses locale-aware number formatting (`Intl.NumberFormat`)
- [ ] **Date/time formatting** - Uses locale-aware date/time formatting (`Intl.DateTimeFormat`) with timezone support
- [ ] **Currency formatting** - Uses `Intl.NumberFormat` with currency support
- [ ] **RTL support** - Layout adapts to right-to-left languages (Arabic, Hebrew) via `dir="rtl"` and logical properties
- [ ] **Text expansion** - UI accommodates text expansion (German can be 30% longer than English)
- [ ] **Language switcher** - Mechanism to change locale is accessible and persistent
- [ ] **Locale detection** - Detects user's preferred locale from browser settings or user preference
- [ ] **Translation fallbacks** - Graceful fallback when translation missing (show key or fallback language)
- [ ] **Contextual translations** - Same word with different meanings has separate translation keys

## Frontend Patterns - Expanded

- [ ] **Component composition** - Prefer composition over inheritance; use children/slots for flexibility
- [ ] **Prop drilling** - Avoid excessive prop drilling (>3 levels); use context/state management instead
- [ ] **Controlled vs uncontrolled** - Forms use controlled components consistently or document why uncontrolled
- [ ] **Single responsibility** - Components have single, clear responsibility; extract when doing too much
- [ ] **Pure components** - Components are pure functions of props (same props = same output)
- [ ] **Side effects isolated** - Side effects in appropriate lifecycle hooks/effects, not during render
- [ ] **Key prop** - Lists use stable, unique keys (not array index unless static list)
- [ ] **Prop validation** - PropTypes (React) or TypeScript types for all component props
- [ ] **Default props** - Provide sensible defaults for optional props
- [ ] **Conditional rendering** - Use consistent pattern (`&&`, ternary, or early return)
- [ ] **Event handlers** - Named event handlers (not inline arrow functions in JSX for better performance)

## React-Specific Patterns

- [ ] **Hooks rules** - Hooks called at top level (not in conditionals, loops, or nested functions)
- [ ] **useEffect dependencies** - Dependency arrays complete and correct; no unnecessary dependencies
- [ ] **useCallback/useMemo** - Used appropriately for expensive computations or stable references (not prematurely)
- [ ] **Custom hooks** - Extract reusable logic into custom hooks with clear names (`use` prefix)
- [ ] **Context performance** - Context values memoized to prevent unnecessary re-renders
- [ ] **Refs appropriately** - Use refs for DOM access or mutable values, not state that triggers re-renders
- [ ] **Fragment usage** - Use `<></>` or `<Fragment>` instead of unnecessary wrapper divs
- [ ] **Strict mode compatible** - Component works correctly in React StrictMode (no double-effect issues)
- [ ] **Error boundaries** - Critical UI sections wrapped in error boundaries with fallback UI
- [ ] **Suspense boundaries** - Async components wrapped in Suspense with loading states
- [ ] **Server components** - Use React Server Components where appropriate (Next.js App Router)

## Vue-Specific Patterns

- [ ] **Composition API** - Prefer Composition API over Options API for complex logic (Vue 3)
- [ ] **Reactivity pitfalls** - Avoid common reactivity gotchas (destructuring props, mutating reactive objects)
- [ ] **Computed vs methods** - Use computed properties for derived state (cached); methods for actions
- [ ] **Watchers appropriately** - Use watchers sparingly; prefer computed properties when possible
- [ ] **Lifecycle hooks** - Use appropriate lifecycle hooks (onMounted, onUnmounted, etc.)
- [ ] **Template refs** - Use template refs correctly for DOM access
- [ ] **Slots effectively** - Use named slots and scoped slots for flexible component composition
- [ ] **Teleport usage** - Use Teleport for modals, tooltips, and portals

## Svelte-Specific Patterns

- [ ] **Reactive declarations** - Use `$:` for derived state and side effects appropriately
- [ ] **Store usage** - Use writable/readable/derived stores correctly; subscribe/unsubscribe properly
- [ ] **Component events** - Use `createEventDispatcher` for component communication
- [ ] **Bindings** - Use two-way bindings (`bind:value`) appropriately; avoid overuse
- [ ] **Transitions** - Transitions and animations use Svelte's built-in system
- [ ] **Actions** - Reusable DOM logic extracted into actions (`use:action`)
- [ ] **Context API** - Use `setContext`/`getContext` for dependency injection

## State Management

- [ ] **Local vs global** - State kept as local as possible; only global when truly shared
- [ ] **State normalization** - Complex state normalized (flat structure, no deep nesting)
- [ ] **Derived state** - Computed/derived values not stored in state (calculate on-the-fly)
- [ ] **State updates immutable** - State updates immutable (no direct mutation)
- [ ] **Action naming** - Actions/mutations have clear, descriptive names (`fetchUserSuccess` vs `setData`)
- [ ] **Selector memoization** - Selectors memoized to prevent unnecessary recalculations
- [ ] **Store structure** - Store organized by domain/feature, not by data type
- [ ] **Middleware usage** - Middleware used appropriately (logging, async handling)

## CSS and Styling

- [ ] **CSS methodology** - Consistent methodology (BEM, CSS Modules, Styled Components, Tailwind)
- [ ] **Scoped styles** - Styles scoped to components (CSS Modules, Svelte scoped, Vue scoped, Styled Components)
- [ ] **No inline styles** - Avoid inline styles except for dynamic values
- [ ] **CSS variables** - Use CSS custom properties for theming and dynamic values
- [ ] **Responsive design** - Mobile-first responsive design with appropriate breakpoints
- [ ] **Flexbox/Grid** - Modern layout techniques (Flexbox, Grid) instead of floats/tables
- [ ] **Logical properties** - Use logical properties for RTL support (`margin-inline-start` vs `margin-left`)
- [ ] **Avoid !important** - Avoid `!important` unless absolutely necessary; use specificity correctly
- [ ] **CSS reset/normalize** - Consistent baseline styles across browsers
- [ ] **Print styles** - Print stylesheets for printable content
- [ ] **Dark mode support** - Theme switching support if applicable (prefers-color-scheme, manual toggle)

## Performance Optimization

- [ ] **Code splitting** - Route-based code splitting; lazy load heavy components
- [ ] **Tree shaking** - Dead code elimination enabled; imports optimized
- [ ] **Bundle size** - Bundle size monitored; heavy dependencies justified
- [ ] **Image optimization** - Images optimized (WebP/AVIF), lazy loaded, responsive sizes
- [ ] **Web Vitals** - Core Web Vitals optimized (LCP <2.5s, FID <100ms, CLS <0.1)
- [ ] **Memoization** - Expensive computations memoized (React.memo, useMemo, Vue computed)
- [ ] **Virtual scrolling** - Long lists use virtual scrolling (react-window, vue-virtual-scroller)
- [ ] **Debounce/throttle** - Input handlers debounced/throttled appropriately
- [ ] **Fonts optimized** - Web fonts optimized (font-display: swap, subset, preload)
- [ ] **Third-party scripts** - Third-party scripts loaded async/defer or dynamically
- [ ] **Service workers** - Service workers for offline support and caching (PWA)
- [ ] **Prefetch/preload** - Critical resources preloaded; next pages prefetched

## SEO Considerations

- [ ] **Meta tags** - Proper meta tags (title, description, Open Graph, Twitter Cards)
- [ ] **Semantic HTML** - Use semantic HTML for better crawling
- [ ] **Server-side rendering** - SSR/SSG for public-facing pages (Next.js, Nuxt, SvelteKit)
- [ ] **Structured data** - Schema.org JSON-LD for rich results
- [ ] **Sitemap** - XML sitemap generated and submitted
- [ ] **Robots.txt** - Proper robots.txt configuration
- [ ] **Canonical URLs** - Canonical URLs set to avoid duplicate content
- [ ] **Internal linking** - Proper internal linking structure
- [ ] **Page titles unique** - Each page has unique, descriptive title
- [ ] **Image alt text** - All images have descriptive alt text (also accessibility)

## Error Handling

- [ ] **Error boundaries** - React Error Boundaries catch rendering errors (or framework equivalent)
- [ ] **Global error handler** - Global error handler for unhandled promise rejections
- [ ] **User-friendly errors** - Error messages are user-friendly, not technical stack traces
- [ ] **Error logging** - Errors logged to monitoring service (Sentry, LogRocket, etc.)
- [ ] **Fallback UI** - Graceful degradation with fallback UI when errors occur
- [ ] **Retry logic** - Transient errors (network) have retry logic
- [ ] **Error context** - Errors include context (user action, component, state)

## Form Handling

- [ ] **Form validation** - Client-side validation with clear error messages
- [ ] **Server validation** - Server-side validation as well (never trust client)
- [ ] **Submit states** - Loading, success, error states handled
- [ ] **Disable on submit** - Submit button disabled during submission (prevent double-submit)
- [ ] **Field-level validation** - Real-time validation for individual fields
- [ ] **Form libraries** - Consider form libraries (Formik, React Hook Form, VeeValidate) for complex forms
- [ ] **Autocomplete** - Proper autocomplete attributes for better UX
- [ ] **Input masking** - Input masking for formatted inputs (phone, credit card)
- [ ] **Password visibility** - Password visibility toggle for better UX
- [ ] **Form persistence** - Consider persisting form state (localStorage) for long forms

## Data Fetching Patterns

- [ ] **Loading states** - Show loading indicators during data fetching
- [ ] **Error states** - Handle and display errors gracefully
- [ ] **Empty states** - Handle empty data with helpful messaging
- [ ] **Caching strategy** - Appropriate caching strategy (SWR, React Query, Apollo Cache)
- [ ] **Stale data** - Handle stale data appropriately (revalidation, background refetch)
- [ ] **Optimistic updates** - Optimistic UI updates for better perceived performance
- [ ] **Infinite scroll** - Infinite scroll/pagination for large datasets
- [ ] **Prefetching** - Prefetch data for likely next actions (hover, route change)
- [ ] **Request cancellation** - Cancel in-flight requests on component unmount or new request
- [ ] **Polling appropriately** - Use polling sparingly; prefer WebSockets/SSE for real-time updates

## Bundle and Build Optimization

- [ ] **Environment variables** - Sensitive keys not in client bundle; use server-side only
- [ ] **Source maps** - Production source maps uploaded to error tracking, not served publicly
- [ ] **Compression** - Gzip/Brotli compression enabled
- [ ] **Minification** - JS/CSS minified in production builds
- [ ] **Asset hashing** - Assets have content hashes for cache busting
- [ ] **Chunk splitting** - Vendor chunks separated from app code
- [ ] **Analyze bundle** - Regularly analyze bundle with webpack-bundle-analyzer or equivalent
- [ ] **Remove console logs** - Console logs removed or disabled in production

---

**Last Updated:** 2025-11-28
**Tier:** 2 (Progressive Disclosure)
**Loaded for:** .tsx, .jsx, .vue, .svelte files
