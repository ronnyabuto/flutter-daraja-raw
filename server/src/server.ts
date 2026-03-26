import 'dotenv/config'
import express, { Request, Response } from 'express'
import cors from 'cors'
import { Pool } from 'pg'
import {
  MpesaStk,
  PostgresAdapter,
  validateCallbackStructure,
  type Logger,
} from 'mpesa-stk'

function requireEnv(name: string): string {
  const value = process.env[name]
  if (!value) throw new Error(`Missing required environment variable: ${name}`)
  return value
}

const config = {
  consumerKey:    requireEnv('MPESA_CONSUMER_KEY'),
  consumerSecret: requireEnv('MPESA_CONSUMER_SECRET'),
  shortCode:      requireEnv('MPESA_SHORTCODE'),
  passKey:        requireEnv('MPESA_PASSKEY'),
  callbackUrl:    requireEnv('MPESA_CALLBACK_URL'),
  environment:    requireEnv('MPESA_ENVIRONMENT') as 'sandbox' | 'production',
}

const DATABASE_URL = requireEnv('DATABASE_URL')
const PORT = parseInt(process.env['PORT'] ?? '3000', 10)

const pool = new Pool({ connectionString: DATABASE_URL })
const adapter = new PostgresAdapter(pool)

const logger: Logger = {
  info:  (msg, meta) => console.log(`[mpesa-stk] INFO  ${msg}`, meta ?? ''),
  warn:  (msg, meta) => console.warn(`[mpesa-stk] WARN  ${msg}`, meta ?? ''),
  error: (msg, meta) => console.error(`[mpesa-stk] ERROR ${msg}`, meta ?? ''),
}

const mpesa = new MpesaStk(config, adapter, logger)

mpesa.onPaymentSettled((payment) => {
  console.log(
    `[settled] id=${payment.id} status=${payment.status} receipt=${payment.mpesaReceiptNumber ?? 'N/A'}`
  )
})

const app = express()
app.use(cors())
app.use(express.json())

app.post('/mpesa/callback', async (req: Request, res: Response) => {
  if (!validateCallbackStructure(req.body)) {
    res.status(400).json({ error: 'Invalid callback structure' })
    return
  }
  // Acknowledge Safaricom before any async work — they timeout at ~5s
  res.json({ ResultCode: 0, ResultDesc: 'Success' })
  try {
    const result = await mpesa.processCallback(req.body)
    console.log(
      `[callback] paymentId=${result.paymentId} status=${result.status} isDuplicate=${result.isDuplicate}`
    )
  } catch (err) {
    console.error('[callback] processCallback error (response already sent):', err)
  }
})

app.post('/mpesa/pay', async (req: Request, res: Response) => {
  const { phoneNumber, amount, reference } = req.body as {
    phoneNumber?: string
    amount?: number
    reference?: string
  }

  if (!phoneNumber || !amount || !reference) {
    res.status(400).json({ error: 'phoneNumber, amount, and reference are required' })
    return
  }

  try {
    const result = await mpesa.initiatePayment({
      phoneNumber,
      amount,
      accountReference: reference,
      description:      `Payment request ${reference}`,
      idempotencyKey:   reference, // prevents double-charge on retry
    })

    console.log(`[pay] initiated checkoutRequestId=${result.checkoutRequestId}`)
    res.json({
      checkoutRequestId: result.checkoutRequestId,
      paymentId:         result.paymentId,
    })
  } catch (err) {
    console.error('[pay] error:', err)
    res.status(502).json({ error: err instanceof Error ? err.message : 'Daraja request failed' })
  }
})

app.get('/mpesa/status/:checkoutRequestId', async (req: Request, res: Response) => {
  const { checkoutRequestId } = req.params as { checkoutRequestId: string }

  try {
    const record = await adapter.getPaymentByCheckoutId(checkoutRequestId)
    if (!record) {
      res.status(404).json({ error: 'Payment not found' })
      return
    }
    res.json({
      status:        record.status,
      receiptNumber: record.mpesaReceiptNumber ?? null,
      failureReason: record.failureReason ?? null,
      resultCode:    record.resultCode ?? null,
    })
  } catch (err) {
    console.error('[status] query error:', err)
    res.status(500).json({ error: 'Query failed' })
  }
})

app.post('/mpesa/reconcile', async (_req: Request, res: Response) => {
  const from = new Date(Date.now() - 24 * 60 * 60 * 1000) // 24h ago
  const to   = new Date(Date.now() -  5 * 60 * 1000)       // 5 min ago

  try {
    const result = await mpesa.reconcile(from, to)
    console.log(
      `[reconcile] checked=${result.checked} matched=${result.matched} skipped=${result.skipped} mismatches=${result.mismatches.length}`
    )
    res.json(result)
  } catch (err) {
    console.error('[reconcile] error:', err)
    res.status(500).json({ error: 'Reconciliation failed' })
  }
})

;(async () => {
  try {
    await adapter.migrate()
    console.log('[db] migrations complete')
  } catch (err) {
    console.error('[db] migration error (continuing):', err)
  }

  app.listen(PORT, () => {
    console.log(`[server] listening on port ${PORT}`)
    console.log(`[server] environment: ${config.environment}`)
    console.log(`[server] callback URL: ${config.callbackUrl}`)
  })
})()
