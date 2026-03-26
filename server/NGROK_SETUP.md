# ngrok Setup — flutter-daraja-raw

## Assigned dev domain

```
unsimular-pianic-rosalinda.ngrok-free.dev
```

Permanent domain tied to the ngrok account. Stable between restarts — the tunnel process is not.

---

## Start the tunnel

```bash
ngrok http --url=unsimular-pianic-rosalinda.ngrok-free.dev 3000
```

> Note: `--domain` is deprecated in ngrok v3.37.2+. Use `--url`.

Keep this running in a dedicated terminal. If it exits, callbacks stop arriving with no grace period or queuing.

---

## Verify the tunnel is working

Test the callback guard — expect HTTP 400 JSON, not an HTML page:

```bash
curl -s -w "\nHTTP %{http_code}" \
  -X POST https://unsimular-pianic-rosalinda.ngrok-free.dev/mpesa/callback \
  -H "Content-Type: application/json" \
  -d '{"test": true}'
```

Expected:
```json
{"error":"Invalid callback structure"}
```
HTTP 400

If you get an HTML page, ngrok's free-tier interstitial is active and Safaricom will also be blocked.

Test server reachability — expect HTTP 500 JSON until PostgreSQL is running:

```bash
curl -s -w "\nHTTP %{http_code}" \
  https://unsimular-pianic-rosalinda.ngrok-free.dev/mpesa/status/test
```

---

## ngrok request inspector

http://127.0.0.1:4040

Every Safaricom request to the callback URL appears here in real time — full headers, body, and response. Keep it open during testing.

---

## Interstitial finding

No interstitial was observed. curl to the ngrok domain returned JSON from Express directly. Safaricom can POST to the callback URL without browser interaction.

Verified with ngrok v3.37.2, authenticated free-tier account, static dev domain. Unauthenticated tunnels and random-URL tunnels behave differently.

---

## Critical operational note

If the ngrok process dies, Safaricom's callback has nowhere to land. The payment stays PENDING in the DB. No queuing, no retry on restart.

---

## Startup checklist

1. `sudo service postgresql start`
2. `cd server && npm run dev`
3. `ngrok http --url=unsimular-pianic-rosalinda.ngrok-free.dev 3000`
4. Verify tunnel: run the curl test above, confirm HTTP 400 JSON
5. Open inspector: http://127.0.0.1:4040
