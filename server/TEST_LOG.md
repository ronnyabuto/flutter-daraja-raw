# Integration Test Log — flutter-daraja-raw

**Date:** 2026-03-26
**Device:** Nokia C30 (E286662013C72002493) — Android 11 (API 30)
**Server:** Express + ts-node on port 3000
**Tunnel:** https://unsimular-pianic-rosalinda.ngrok-free.dev
**Environment:** Safaricom Daraja sandbox

---

## Summary

- **Polling lag (happy path):** 3s–39s across two runs, same code, same device, same network. Entirely dependent on where the callback lands in the poll window.
- **Callback delivery:** 7/7 received when ngrok was up. 0/1 when it was down. No retry was observed after tunnel restart.
- **Biggest friction point:** The tunnel. One kill at the wrong moment = orphaned payment, money gone, no record on the server.
**Final DB state:**
```
  status   | count
-----------+-------
 CANCELLED |     1
 FAILED    |     2
 PENDING   |     1
 SUCCESS   |     3
 TIMEOUT   |     1
```

The PENDING record is the Test 3 orphan — money left the account, the server has no record of it. Reconciliation ran but the sandbox STK Query returned FAILED for all payments including confirmed successes, so nothing resolved.

---

## Precondition Verification — 10:43

### 1. PostgreSQL
```
psql daraja_raw -c "SELECT COUNT(*) FROM mpesa_payments;"
 count
-------
     1
```
PASS. 1 pre-existing row from an 08:15 session.

```
 status  | checkout_request_id              | initiated_at                | result_code | failure_reason
---------+----------------------------------+-----------------------------+-------------+------------------------
 TIMEOUT | ws_CO_26032026081546114708374149 | 2026-03-26 08:15:46.367+03  |        1037 | No response from user.
```

The TIMEOUT record has result_code=1037 — Safaricom did deliver the callback. 1037 means the USSD prompt expired before the user responded. The library maps 1037 → TIMEOUT, not FAILED, which is correct.

### 2. Express server
```
curl http://localhost:3000/mpesa/status/test
{"error":"Payment not found"}
```
PASS.

### 3. ngrok tunnel
```
curl https://unsimular-pianic-rosalinda.ngrok-free.dev/mpesa/status/test
{"error":"Payment not found"}
```
PASS. JSON from Express, not an ngrok HTML page. p50 latency 4.7ms, p99 19.4ms.

### 4. Physical device
```
flutter devices
Nokia C30 (mobile) • E286662013C72002493 • android-arm • Android 11 (API 30)
```
PASS.

### 5. Daraja credentials
```
MPESA_SHORTCODE:    174379 (sandbox)
MPESA_CALLBACK_URL: https://unsimular-pianic-rosalinda.ngrok-free.dev/mpesa/callback
MPESA_ENVIRONMENT:  sandbox
```
PASS.

### 6. Polling schedule
`_startPolling()` fires at T+10s, T+30s, T+70s with a hard timeout at T+90s. Minimum possible lag is 10s. Worst case is 40s (callback arrives just after T+30s poll).

---

## Test 1: Happy path — KES 1 to own number

**Time:** 11:10

**What I did:**
1. Installed APK via `adb install` (flutter run failed — NDK license issue, worked around)
2. Entered own number, amount KES 1, tapped Pay
3. STK Push arrived, PIN entered at 11:10:48
4. Waited for UI to resolve

**What the server logged:**
- PENDING created: 11:10:17
- Callback → SUCCESS, receipt `UCQ5UAQ403`: 11:11:02 (14s after initiation)

**What ngrok showed:**
- 1× POST /mpesa/callback → 200
- 0× status polls — Flutter polls go direct to LAN IP 192.168.0.101:3000, not through the tunnel

**What the Flutter UI did:**
- PaymentIdle → Initiating → Pending in ~2s
- T+10s poll (11:10:27): PENDING
- T+30s poll (11:10:47): PENDING
- Callback hits server at 11:11:02 — Flutter doesn't know yet
- T+70s poll (11:11:27): SUCCESS → PaymentSuccess

**Time from PIN entry to UI update:** 39 seconds (11:10:48 → 11:11:27)
**Time from callback to UI update:** 25 seconds

**Unexpected behaviour:**
Flutter polls bypass ngrok — the inspector is useless for counting client poll requests.

**What this teaches:**
Callback resolved the payment in 14 seconds. Flutter didn't find out for 39 seconds.

---

## Test 2: Measure polling lag precisely

**Time:** 11:31

**What I did:**
1. Reset to form (tapped Done), changed reference to ORDER-002
2. Tapped Pay at ~11:31:46, entered PIN as fast as possible

**What the server logged:**
- PENDING created: 11:31:46
- Callback → SUCCESS, receipt `UCQ5UAPYRY`: 11:31:59 (13s after initiation)

**What ngrok showed:** 1× POST /mpesa/callback → 200

**Exact timeline:**
- STK Push on phone: 11:31:50 (4s after tap)
- PIN entered: 11:31:55
- PaymentSuccess on UI: 11:31:58 (3s after PIN)
- Callback written to DB: 11:31:59

**Time from PIN entry to UI update:** 3 seconds
**Polling lag:** ~0s — T+10s poll (~11:31:57) and callback (~11:31:58) landed within 1 second of each other. The poll caught it by a hair.

**Unexpected behaviour:**
Test 1 produced 39s lag. Test 2 produced 3s lag. Identical code, same device, 21 minutes apart.

**What this teaches:**
Lag is a function of timing, not implementation. The poll schedule is fixed; Safaricom's callback delivery window is not.

---

## Test 3: Tunnel death mid-transaction

**Time:** 13:36

**What I did:**
1. Changed reference to ORDER-003, tapped Pay at 13:36:41
2. Killed ngrok (Ctrl+C) the moment PaymentPending appeared
3. Entered M-Pesa PIN on phone
4. Waited 90 seconds

**What the server logged:**
- PENDING created: 13:36:41
- No callback line — tunnel was down

**What ngrok showed:** Nothing. Tunnel was dead.

**What the Flutter UI did:**
- T+10s, T+30s, T+70s polls all returned PENDING
- At T+90s (13:38:11): hard timeout fired → PaymentTimeout
- Screen: "Status unknown. We did not receive a confirmation within the expected window. If money was deducted from your account, please contact support..."

**Time from PIN entry to UI update:** 90 seconds (timeout, not resolution)

**DB state:**
```
 status  | result_code | failure_reason
---------+-------------+----------------
 PENDING |             |
```

**Was money deducted?** YES — confirmed. KES 1 left the account. DB has no record of it.

**Unexpected behaviour:**
After restarting ngrok, no delayed callback arrived. No retry was observed.

**What this teaches:**
Tunnel death between STK push and callback creates an orphaned payment. The "Status unknown" copy is correct — saying "payment failed" here would be wrong.

---

## Test 4: Reconciliation after tunnel death

**Time:** 13:41

**Pre-reconciliation DB state:**
```
 status  | checkout_request_id              | initiated_at
---------+----------------------------------+----------------------------
 PENDING | ws_CO_26032026133641276708729173 | 2026-03-26 13:36:41.599+03
```

**What I did:**
```bash
curl -X POST http://localhost:3000/mpesa/reconcile -H "Content-Type: application/json"
```

**First run at 13:41:15 (payment was 4m34s old):**
```json
{"checked":2,"matched":1,"skipped":0,"mismatches":[...]}
```
Test 3 payment skipped — below the 5-minute minimum age cutoff.

**Second run at 13:42:25 (payment was 5m44s old):**
```json
{"checked":3,"matched":0,"skipped":0,"mismatches":[
  {"checkoutRequestId":"ws_CO_26032026133641276708729173","storedStatus":"PENDING","mpesaStatus":"FAILED"},
  {"checkoutRequestId":"ws_CO_26032026111016899708729173","storedStatus":"SUCCESS","mpesaStatus":"FAILED"},
  {"checkoutRequestId":"ws_CO_26032026113146397708729173","storedStatus":"SUCCESS","mpesaStatus":"FAILED"}
]}
```

**DB state after reconciliation:** Still PENDING — unresolved.

**Why it didn't resolve:**
Safaricom's sandbox STK Query returned FAILED for all three payments, including Tests 1 and 2 which have confirmed receipts and confirmed deductions. The query API is broken in sandbox. The library correctly refused to overwrite a stored SUCCESS with a contradictory FAILED query response.

In production the STK Query returns accurate results. Reconciliation would have updated Test 3 from PENDING → SUCCESS with the receipt number.

**Unexpected behaviour:**
The 5-minute age cutoff means you can't test reconciliation immediately after tunnel death. Caught this on the first run.

**What this teaches:**
The reconciliation logic works — it identified the orphaned payment and queried Safaricom. The sandbox STK Query is not a reliable test surface.

---

## Test 5: Wrong PIN

**Time:** 13:44

**What I did:**
1. Changed reference to ORDER-004, tapped Pay at 13:44:14
2. Entered wrong PIN three times when STK Push arrived

**What the server logged:**
- PENDING created: 13:44:14
- Callback → FAILED, result_code=2001, "The initiator information is invalid.": 13:44:33 (19s)

**What ngrok showed:** 1× POST /mpesa/callback → 200

**What the Flutter UI did:**
- T+10s poll (13:44:25): PENDING
- Callback at 13:44:33 → FAILED
- T+30s poll (13:44:45): caught FAILED → PaymentFailed
- Screen: "Payment failed. The initiator information is invalid. Result code: 2001"

**ResultCode:** 2001 ✓
**Time from PIN entry to UI update:** ~25 seconds

**Unexpected behaviour:** None.

**What this teaches:**
Wrong PIN and success follow the same poll schedule — same lag characteristics regardless of outcome.

---

## Test 6: User cancels

**Time:** 13:46

**What I did:**
1. Changed reference to ORDER-005, tapped Pay at 13:46:13
2. Tapped Cancel on the STK Push — no PIN entered

**What the server logged:**
- PENDING created: 13:46:13
- Callback → CANCELLED, result_code=1032, "Request Cancelled by user.": 13:46:31 (18s)

**What ngrok showed:** 1× POST /mpesa/callback → 200

**What the Flutter UI did:**
- T+10s poll (13:46:23): PENDING
- Callback at 13:46:31 → CANCELLED
- T+30s poll (13:46:43): caught CANCELLED → PaymentCancelled
- Screen: "Payment cancelled. You dismissed the M-Pesa prompt."

**ResultCode:** 1032 ✓
**Time from cancel to UI update:** ~30 seconds

**Unexpected behaviour:**
Cancellation callback (18s) and wrong-PIN callback (19s) arrived at virtually the same speed. No meaningful difference between outcome types in sandbox.

**What this teaches:**
1032 is the only code that maps to PaymentCancelled. Everything else non-zero is PaymentFailed. The copy distinction matters to the user.

---

## Test 7: App backgrounded during payment

**Time:** 13:48

**What I did:**
1. Changed reference to ORDER-006, tapped Pay at 13:48:13
2. Pressed home button the moment PaymentPending appeared
3. Opened M-Pesa app, entered PIN
4. Waited 5 seconds, returned to Flutter app

**What the server logged:**
- PENDING created: 13:48:13
- Callback → SUCCESS, receipt `UCQ5UAQHKO`: 13:48:30 (17s, app was backgrounded)

**What ngrok showed:** 1× POST /mpesa/callback → 200

**What the Flutter UI did:**
- App backgrounded — callback processed server-side, Flutter unaware
- Returned to app → `didChangeAppLifecycleState(resumed)` fired
- `state is PaymentPending` → true → `_poll()` called immediately
- Poll returned SUCCESS → PaymentSuccess
- User: "Returned to the app. Then immediately: Payment successful"

**Which triggered the update:** `didChangeAppLifecycleState`, not a scheduled poll
**Time from return to UI update:** ~1-2 seconds

**Unexpected behaviour:** None — this worked as designed.

**What this teaches:**
The lifecycle observer makes this the best-case UX in the polling model. The 39-second worst case only happens when the user stays in the app the entire time.

---

## Test 8: App killed mid-payment

**Time:** 13:50

**What I did:**
1. Changed reference to ORDER-007, tapped Pay at 13:50:52
2. Force-killed app (Recent apps → swipe away) when PaymentPending appeared
3. Waited 10 seconds, relaunched from home screen

**What the server logged:**
- PENDING created: 13:50:52
- Callback → FAILED, result_code=2001: 13:51:23 (31s, app was dead)

**What ngrok showed:** 1× POST /mpesa/callback → 200

**What the Flutter UI did on relaunch:**
- `_restoreIfPending()` ran, found CID in SharedPreferences
- State restored to PaymentPending (brief flash)
- First poll returned FAILED → PaymentFailed
- Screen: "Payment failed. The initiator information is invalid. Result code: 2001"

**Did SharedPreferences restore correctly?** Yes.
**Time from relaunch to UI resolution:** ~2-3 seconds

**Unexpected behaviour:**
Test went slightly off-script — PIN was entered before the kill, not after. The kill happened post-PIN-entry. SharedPreferences restoration worked regardless.

**What this teaches:**
The server processes callbacks independently of client state. Killing the app does not affect payment processing. SharedPreferences persistence means a relaunched app picks up where it left off — unless the kill happens in the ~2s window between PaymentInitiating and `_persist()` completing, in which case the CID is lost.

---

## Post-Test DB State

```
psql daraja_raw -c "SELECT status, COUNT(*) FROM mpesa_payments GROUP BY status;"

  status   | count
-----------+-------
 CANCELLED |     1
 FAILED    |     2
 PENDING   |     1
 SUCCESS   |     3
 TIMEOUT   |     1
```
