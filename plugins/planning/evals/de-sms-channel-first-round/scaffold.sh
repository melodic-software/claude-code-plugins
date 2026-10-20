#!/usr/bin/env bash
# Seeds a small email-only notifications module and the Brief for adding an SMS channel.
set -euo pipefail

mkdir -p notifications tests .work/sms-notifications
cat >notifications/__init__.py <<'PY'
PY
cat >notifications/email_sender.py <<'PY'
import smtplib
from email.message import EmailMessage


class EmailSender:
    def __init__(self, host: str, port: int, from_addr: str) -> None:
        self._host = host
        self._port = port
        self._from = from_addr

    def send(self, to_addr: str, subject: str, body: str) -> None:
        msg = EmailMessage()
        msg["From"] = self._from
        msg["To"] = to_addr
        msg["Subject"] = subject
        msg.set_content(body)
        with smtplib.SMTP(self._host, self._port) as smtp:
            smtp.send_message(msg)
PY
cat >notifications/dispatcher.py <<'PY'
from notifications.email_sender import EmailSender


class Dispatcher:
    """Sends each user notification by email."""

    def __init__(self, email: EmailSender) -> None:
        self._email = email

    def notify(self, user: dict, subject: str, body: str) -> None:
        self._email.send(user["email"], subject, body)
PY
cat >tests/test_dispatcher.py <<'PY'
from notifications.dispatcher import Dispatcher


class FakeEmail:
    def __init__(self):
        self.sent = []

    def send(self, to_addr, subject, body):
        self.sent.append((to_addr, subject, body))


def test_notify_sends_email():
    fake = FakeEmail()
    Dispatcher(fake).notify({"email": "a@example.com"}, "Hi", "Body")
    assert fake.sent == [("a@example.com", "Hi", "Body")]
PY
cat >.work/sms-notifications/PLAN.md <<'MD'
# SMS notifications

## Brief

### Problem

- **Gap:** notifications reach users only by email, so users away from their inbox miss them.
- **Who / how many:** users who have asked for text alerts; support counts about 40 such requests.
- **Frequency:** every notification for those users.
- **Trend:** growing; requests rose each month this quarter.
- **Cost:** missed notifications lead to late responses and follow-up support tickets.
- **Evidence:** support's request tally (reported); no delivery metric for missed email exists.

### Goal

Users who opt in also receive their notifications by SMS, sent through Twilio.

### Work size

- **Appetite:** Medium. A real piece of work the human will fund with some care.
- **Size:** Medium. Several coordinated changes inside one deliverable.
- **Uncertainty:** Knowable. The open points can be settled by looking.
- **Split signals:** none.

### Constraints

- Email keeps working exactly as today for users who do not opt in.
- Twilio is the only SMS provider under contract; no second provider is planned.

### Acceptance criteria

- An opted-in user with a phone number gets the SMS and the email for each notification.
- A Twilio outage never blocks the email.
MD
