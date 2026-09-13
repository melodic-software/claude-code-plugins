# Web and API surface security checklist

Loaded on demand by this plugin's `security-reviewer` agent when the change set exposes a web or
API surface, whichever ecosystem implements it. The OWASP table and the cross-ecosystem list in the
agent body are the floor for every review; these are the surface-specific additions that floor does
not cover.

- **Headers**: strict CSP (no un-nonced inline scripts), HSTS (1-year minimum), `X-Content-Type-Options: nosniff`, `Referrer-Policy`
- **Cookies**: Secure + HttpOnly + SameSite on session/auth cookies; never store secrets in non-HttpOnly cookies
- **CSRF**: anti-forgery token on state-changing endpoints; SameSite alone is not sufficient
- **JWT**: alg allowlist (no `none`); signature verified; exp/nbf/iss/aud validated
- **Sessions**: regenerate ID on privilege escalation; idle and absolute timeouts
