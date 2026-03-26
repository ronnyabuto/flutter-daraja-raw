sealed class PaymentState {
  const PaymentState();
}

/// No payment in progress. The form is shown.
class PaymentIdle extends PaymentState {
  const PaymentIdle();
}

/// STK Push request is in flight to the Express server.
class PaymentInitiating extends PaymentState {
  const PaymentInitiating();
}

/// STK Push accepted by Safaricom. USSD prompt delivered to the customer's phone.
/// We have no further information until the callback arrives at our server.
/// checkoutRequestId persisted to SharedPreferences so it survives app restarts.
class PaymentPending extends PaymentState {
  final String checkoutRequestId;
  final DateTime initiatedAt;
  final int amount;
  const PaymentPending({
    required this.checkoutRequestId,
    required this.initiatedAt,
    required this.amount,
  });
}

/// ResultCode 0: payment confirmed.
class PaymentSuccess extends PaymentState {
  final String checkoutRequestId;
  final String receiptNumber;
  final int amount;
  const PaymentSuccess({
    required this.checkoutRequestId,
    required this.receiptNumber,
    required this.amount,
  });
}

/// ResultCode non-zero (excluding 1032).
///   1    → insufficient funds
///   2001 → wrong PIN
///   1019 → transaction expired
///   1025 → activity in progress
///   1037 → USSD push timed out
class PaymentFailed extends PaymentState {
  final String checkoutRequestId;
  final int resultCode;
  final String message;
  const PaymentFailed({
    required this.checkoutRequestId,
    required this.resultCode,
    required this.message,
  });
}

/// ResultCode 1032: user explicitly dismissed the USSD prompt.
class PaymentCancelled extends PaymentState {
  const PaymentCancelled();
}

/// Polling window exhausted with no terminal status.
/// TIMEOUT ≠ FAILED — the customer may have paid after the window closed.
/// Never show "payment failed". Show "status unknown, contact support".
/// /mpesa/reconcile resolves payments that completed after the window.
class PaymentTimeout extends PaymentState {
  final String checkoutRequestId;
  const PaymentTimeout({required this.checkoutRequestId});
}

/// Infrastructure error (network, server 500, JSON parse).
/// Distinct from PaymentFailed — the payment itself may or may not have fired.
class PaymentError extends PaymentState {
  final String message;
  const PaymentError({required this.message});
}
