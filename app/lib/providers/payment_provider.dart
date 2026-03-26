import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/payment_state.dart';
import '../services/payment_service.dart';

const _kCID = 'pending_checkout_request_id';
const _kAmount = 'pending_amount';
const _kInitiatedAt = 'pending_initiated_at';

final paymentProvider = NotifierProvider<PaymentNotifier, PaymentState>(
  PaymentNotifier.new,
);

class PaymentNotifier extends Notifier<PaymentState> with WidgetsBindingObserver {
  final _service = PaymentService();

  Timer? _t1; // T + 10s
  Timer? _t2; // T + 30s
  Timer? _t3; // T + 70s
  Timer? _tTimeout; // T + 90s

  @override
  PaymentState build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _cancelTimers();
    });
    Future.microtask(_restoreIfPending);
    return const PaymentIdle();
  }

  Future<void> _restoreIfPending() async {
    final prefs = await SharedPreferences.getInstance();
    final cid = prefs.getString(_kCID);
    if (cid == null) return;

    final amount = prefs.getInt(_kAmount) ?? 0;
    final initiatedAtMs = prefs.getInt(_kInitiatedAt);
    final initiatedAt = initiatedAtMs != null
        ? DateTime.fromMillisecondsSinceEpoch(initiatedAtMs)
        : DateTime.now();

    debugPrint('[provider] Restoring pending payment: $cid');
    state = PaymentPending(checkoutRequestId: cid, initiatedAt: initiatedAt, amount: amount);
    _startPolling(cid);
  }

  Future<void> pay({
    required String phoneNumber,
    required int amount,
    required String reference,
  }) async {
    if (state is! PaymentIdle) return;
    state = const PaymentInitiating();

    try {
      final result = await _service.initiate(
        phoneNumber: phoneNumber,
        amount: amount,
        reference: reference,
      );

      await _persist(cid: result.checkoutRequestId, amount: amount);

      state = PaymentPending(
        checkoutRequestId: result.checkoutRequestId,
        initiatedAt: DateTime.now(),
        amount: amount,
      );
      _startPolling(result.checkoutRequestId);
    } on FormatException catch (e) {
      state = PaymentError(message: e.message);
    } catch (e) {
      state = PaymentError(message: e.toString());
    }
  }

  Future<void> reset() async {
    _cancelTimers();
    await _clearPersisted();
    state = const PaymentIdle();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final current = this.state;
      if (current is PaymentPending) {
        debugPrint('[provider] App resumed — polling immediately');
        _poll(current.checkoutRequestId);
      }
    }
  }

  // Polls at T+10s, T+30s, T+70s with a hard 90s timeout.
  void _startPolling(String cid) {
    _cancelTimers();
    _t1 = Timer(const Duration(seconds: 10), () => _poll(cid));
    _t2 = Timer(const Duration(seconds: 30), () => _poll(cid));
    _t3 = Timer(const Duration(seconds: 70), () => _poll(cid));
    _tTimeout = Timer(const Duration(seconds: 90), () {
      if (state is PaymentPending) {
        _cancelTimers();
        // TIMEOUT ≠ FAILED — do not clear persistence; /mpesa/reconcile can still resolve this.
        state = PaymentTimeout(checkoutRequestId: cid);
      }
    });
  }

  Future<void> _poll(String cid) async {
    if (state is! PaymentPending) return;

    try {
      final result = await _service.getStatus(cid);
      debugPrint('[provider] Poll: $cid → ${result.status}');

      switch (result.status) {
        case 'PENDING':
          break;
        case 'SUCCESS':
          _cancelTimers();
          await _clearPersisted();
          final pending = state as PaymentPending;
          state = PaymentSuccess(
            checkoutRequestId: cid,
            receiptNumber: result.receiptNumber!,
            amount: pending.amount,
          );
        case 'CANCELLED':
          _cancelTimers();
          await _clearPersisted();
          state = const PaymentCancelled();
        case 'FAILED':
        case 'TIMEOUT':
        case 'EXPIRED':
          _cancelTimers();
          await _clearPersisted();
          state = PaymentFailed(
            checkoutRequestId: cid,
            resultCode: result.resultCode ?? -1,
            message: result.failureReason ?? 'Payment ${result.status.toLowerCase()}',
          );
        default:
          debugPrint('[provider] Unknown status: ${result.status}');
      }
    } catch (e) {
      debugPrint('[provider] Poll error (non-fatal): $e');
    }
  }

  void _cancelTimers() {
    _t1?.cancel();
    _t2?.cancel();
    _t3?.cancel();
    _tTimeout?.cancel();
    _t1 = _t2 = _t3 = _tTimeout = null;
  }

  Future<void> _persist({required String cid, required int amount}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCID, cid);
    await prefs.setInt(_kAmount, amount);
    await prefs.setInt(_kInitiatedAt, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _clearPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCID);
    await prefs.remove(_kAmount);
    await prefs.remove(_kInitiatedAt);
  }
}
