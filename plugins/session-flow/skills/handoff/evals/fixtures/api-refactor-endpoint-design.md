# Draft: `GET /v2/orders`

Synthetic eval fixture. Status: draft, not yet reviewed by the platform team.

## Request

`GET /v2/orders?customerId=<id>&status=<open|shipped|cancelled>&since=<ISO-8601>&cursor=<opaque>&limit=<1-100>`

- Every filter is optional; with none, the newest orders the caller may see are returned.
- `limit` defaults to 25.

## Response

```json
{
  "data": [{ "id": "ord_123", "customerId": "cus_9", "status": "open", "createdAt": "2026-10-01T12:00:00Z" }],
  "nextCursor": "b3JkXzEyMg"
}
```

`nextCursor` is absent on the last page.

## Errors

The existing envelope: `400` for a bad filter value, `403` when the scope does not allow the
requested customer.

## Open for review

1. Opaque cursor versus page and page-size.
2. `orders:read` versus a new `orders:read:partner` scope.
3. `GET /v2/orders/{id}` versus `?id=` on the collection.
