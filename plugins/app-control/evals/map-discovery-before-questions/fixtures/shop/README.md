# Shop

A small web shop.

## Run it

```bash
python3 server.py
```

It listens on port 8080. `GET /healthz` returns `{"status": "ok", "build": "<commit>", "db": "local"}`.

## Mail

Password reset mail goes out through the SMTP host in `config/mail.json`, on every run, local
included.
