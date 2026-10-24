# Shop

A small web shop.

## Run it

```bash
python3 server.py
```

It listens on port 8080. `GET /healthz` returns `{"status": "ok", "build": "<commit>", "db": "local"}`.

## Sign-in

Sign-in goes through the team's shared identity server at `https://id.dev.example.com`, local runs
included. Ten failed attempts lock an account for every user of it.

## Mail

Order confirmation mail goes out through the SMTP host in `config/mail.json`, on every run, local
included.
