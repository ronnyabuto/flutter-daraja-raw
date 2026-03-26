# ngrok Setup — flutter-daraja-raw

## Assigned dev domain

```
unsimular-pianic-rosalinda.ngrok-free.dev
```

This domain is permanent and tied to your ngrok account. It does not change
between tunnel restarts. The URL itself is stable — the tunnel process is not.

---

## Start the tunnel

```bash
ngrok http --url=unsimular-pianic-rosalinda.ngrok-free.dev 3000
```

> Note: `--domain` is deprecated in ngrok v3.37.2+. Use `--url` instead.

Leave this process running in a dedicated terminal. If it exits, callbacks stop
arriving immediately — there is no grace period or queuing.

---

## Verify the tunnel is working

### Test the callback guard (expect HTTP 400 JSON — not an HTML page):

```bash
curl -s -w "\nHTTP %{http_code}" \
  -X POST https://unsimular-pianic-rosalinda.ngrok-free.dev/mpesa/callback \
  -H "Content-Type: application/json" \
  -d '{"test": true}'
```

Expected response:
```json
{"error":"Invalid callback structure"}
```
HTTP 400

If you receive an HTML page from ngrok instead, the free-tier interstitial is
active and Safaricom's servers will also be blocked. See note below.

### Test server reachability (expect HTTP 500 JSON until PostgreSQL is running):

```bash
curl -s -w "\nHTTP %{http_code}" \
  https://unsimular-pianic-rosalinda.ngrok-free.dev/mpesa/status/test
```

---

## ngrok request inspector

URL: http://127.0.0.1:4040

Every request Safaricom makes to your callback URL appears here in real time —
full headers, body, and response. This is the primary debugging tool for
callback delivery issues. Keep it open during testing.

---

## Interstitial finding

**No interstitial was observed.** curl to the ngrok domain returned JSON from
Express directly, with no ngrok HTML page interposing. This means:

- Safaricom's servers can POST to the callback URL without browser interaction
- The free plan's assigned domain works for webhook delivery in this test

This was verified with ngrok v3.37.2 using an authenticated free-tier account
with a claimed static dev domain. Unauthenticated tunnels and random-URL tunnels
behave differently — do not assume this result applies to those configurations.

---

## Critical operational note

> **The tunnel must be running for callbacks to reach the server. If the ngrok
> process dies, callbacks are silently dropped. Safaricom will retry once or
> twice and then stop. The payment will remain PENDING in the database until
> the reconciliation endpoint resolves it.**
>
> This is the problem Appwrite Functions solve in Stage 3. An Appwrite Function
> URL is permanently live without a running process on your machine — no tunnel,
> no fragile background process, no missed callbacks.

---

## Startup checklist (every development session)

1. Start PostgreSQL: `sudo service postgresql start`
2. Start Express: `cd server && npm run dev`
3. Start ngrok: `ngrok http --url=unsimular-pianic-rosalinda.ngrok-free.dev 3000`
4. Verify tunnel: run the curl test above, confirm HTTP 400 JSON
5. Open inspector: http://127.0.0.1:4040
