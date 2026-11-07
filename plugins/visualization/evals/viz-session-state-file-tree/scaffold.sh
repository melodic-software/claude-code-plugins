#!/usr/bin/env bash
# Writes the three files the history says the assistant read, with the contents it describes:
# src/sessions/store.ts (SessionStore, live sessions keyed by id), src/sessions/events.ts
# (session-opened and session-closed), src/transport/client.ts (the session token, reconnect).
set -euo pipefail
set -o noclobber

here="$(pwd -P)"
real_home="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 || true)"
case "${here}" in
/ | "${HOME:-/}" | "${real_home:-/}") echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
*) ;;
esac
if [[ -e src ]]; then
  echo "refusing to scaffold: ${here}/src already exists" >&2
  exit 3
fi

mkdir -p src/sessions src/transport
cat >src/sessions/store.ts <<'EOF'
import { emitSessionClosed, emitSessionOpened } from "./events";

export interface Session {
  id: string;
  userId: string;
  openedAt: number;
}

// SessionStore: the in-memory map of live sessions, keyed by session id.
export class SessionStore {
  private readonly live = new Map<string, Session>();

  open(session: Session): void {
    this.live.set(session.id, session);
    emitSessionOpened(session);
  }

  close(id: string): void {
    const session = this.live.get(id);
    if (session === undefined) return;
    this.live.delete(id);
    emitSessionClosed(session);
  }

  get(id: string): Session | undefined {
    return this.live.get(id);
  }
}
EOF
cat >src/sessions/events.ts <<'EOF'
import { EventEmitter } from "node:events";
import type { Session } from "./store";

export const sessionEvents = new EventEmitter();

export function emitSessionOpened(session: Session): void {
  sessionEvents.emit("session-opened", session);
}

export function emitSessionClosed(session: Session): void {
  sessionEvents.emit("session-closed", session);
}
EOF
cat >src/transport/client.ts <<'EOF'
export class Client {
  private sessionToken: string | null = null;
  private socket: WebSocket | null = null;

  constructor(private readonly url: string) {}

  connect(token: string): void {
    this.sessionToken = token;
    this.socket = new WebSocket(`${this.url}?token=${token}`);
    this.socket.addEventListener("close", () => this.reconnect());
  }

  // After a drop, reconnect with the session token held for this connection.
  private reconnect(): void {
    if (this.sessionToken !== null) this.connect(this.sessionToken);
  }
}
EOF
