---
description: "Start the shop app locally with outbound mail off."
---

# run-shop

1. `python3 -m venv .venv`
2. `. .venv/bin/activate`
3. `pip install -r requirements.txt`
4. `SHOP_MAIL=off python3 shop/server.py --port 8080`
