import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/payment_state.dart';
import '../providers/payment_provider.dart';
import '../services/payment_service.dart';

class RequestPaymentScreen extends ConsumerStatefulWidget {
  const RequestPaymentScreen({super.key});

  @override
  ConsumerState<RequestPaymentScreen> createState() =>
      _RequestPaymentScreenState();
}

class _RequestPaymentScreenState extends ConsumerState<RequestPaymentScreen> {
  final _phoneController = TextEditingController();
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController(text: 'ORDER-001');
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _phoneController.dispose();
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref.read(paymentProvider.notifier).pay(
          phoneNumber: _phoneController.text.trim(),
          amount: int.parse(_amountController.text.trim()),
          reference: _referenceController.text.trim(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final paymentState = ref.watch(paymentProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('M-Pesa Payment')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: switch (paymentState) {
            PaymentIdle() => _buildForm(),
            PaymentInitiating() => _buildInitiating(),
            PaymentPending(:final checkoutRequestId, :final initiatedAt, :final amount) =>
              _buildPending(checkoutRequestId, initiatedAt, amount),
            PaymentSuccess(:final receiptNumber, :final amount) =>
              _buildSuccess(receiptNumber, amount),
            PaymentFailed(:final message, :final resultCode) =>
              _buildFailed(message, resultCode),
            PaymentCancelled() => _buildCancelled(),
            PaymentTimeout(:final checkoutRequestId) =>
              _buildTimeout(checkoutRequestId),
            PaymentError(:final message) => _buildError(message),
          },
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Pay with M-Pesa',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone number',
              hintText: '07XX XXX XXX',
              border: OutlineInputBorder(),
              helperText: 'Formats accepted: 07xx, 01xx, +254xx, 254xx',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Enter a phone number';
              try {
                PaymentService.normalisePhone(value.trim());
                return null;
              } on FormatException catch (e) {
                return e.message;
              }
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Amount (KES)',
              hintText: '1',
              border: OutlineInputBorder(),
              helperText: 'Minimum: KES 1. Use KES 1 for sandbox testing.',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Enter an amount';
              final parsed = int.tryParse(value.trim());
              if (parsed == null || parsed < 1) return 'Amount must be at least KES 1';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _referenceController,
            decoration: const InputDecoration(
              labelText: 'Payment reference',
              border: OutlineInputBorder(),
              helperText: 'Shown on the M-Pesa SMS receipt',
            ),
            validator: (value) =>
                (value == null || value.trim().isEmpty) ? 'Enter a reference' : null,
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _submit,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Pay with M-Pesa', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitiating() {
    return const _StatusCard(
      icon: CircularProgressIndicator(),
      title: 'Sending STK Push…',
      body: 'Contacting Safaricom. This usually takes 2–3 seconds.\n\nDo not close the app.',
    );
  }

  Widget _buildPending(String checkoutRequestId, DateTime initiatedAt, int amount) {
    final elapsed = DateTime.now().difference(initiatedAt).inSeconds;
    return _StatusCard(
      icon: const CircularProgressIndicator(),
      title: 'Waiting for payment',
      body: 'A payment prompt has been sent to your phone.\n\n'
          'Enter your M-Pesa PIN to complete the payment.\n\n'
          'Amount: KES $amount\nWaiting: ${elapsed}s',
      trailing: TextButton(
        onPressed: () => ref.read(paymentProvider.notifier).reset(),
        child: const Text('Cancel'),
      ),
    );
  }

  Widget _buildSuccess(String receiptNumber, int amount) {
    return _StatusCard(
      icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
      title: 'Payment successful',
      body: 'Amount: KES $amount\nM-Pesa receipt: $receiptNumber\n\n'
          'You will receive an SMS confirmation from M-Pesa.',
      trailing: FilledButton(
        onPressed: () => ref.read(paymentProvider.notifier).reset(),
        child: const Text('Done'),
      ),
    );
  }

  Widget _buildFailed(String message, int resultCode) {
    return _StatusCard(
      icon: const Icon(Icons.error, color: Colors.red, size: 48),
      title: 'Payment failed',
      body: '$message\n\nResult code: $resultCode',
      trailing: FilledButton(
        onPressed: () => ref.read(paymentProvider.notifier).reset(),
        child: const Text('Try again'),
      ),
    );
  }

  Widget _buildCancelled() {
    return _StatusCard(
      icon: const Icon(Icons.cancel, color: Colors.orange, size: 48),
      title: 'Payment cancelled',
      body: 'You dismissed the M-Pesa prompt.\n\nNo money was deducted.',
      trailing: FilledButton(
        onPressed: () => ref.read(paymentProvider.notifier).reset(),
        child: const Text('Try again'),
      ),
    );
  }

  Widget _buildTimeout(String checkoutRequestId) {
    return _StatusCard(
      icon: const Icon(Icons.access_time, color: Colors.amber, size: 48),
      title: 'Status unknown',
      body: 'We did not receive a confirmation within the expected window.\n\n'
          'If money was deducted from your account, please contact support '
          'with reference: $checkoutRequestId\n\n'
          'Do NOT retry — you may be charged twice.',
      trailing: FilledButton(
        onPressed: () => ref.read(paymentProvider.notifier).reset(),
        child: const Text('Back to form'),
      ),
    );
  }

  Widget _buildError(String message) {
    return _StatusCard(
      icon: const Icon(Icons.warning, color: Colors.red, size: 48),
      title: 'Something went wrong',
      body: message,
      trailing: FilledButton(
        onPressed: () => ref.read(paymentProvider.notifier).reset(),
        child: const Text('Try again'),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final Widget icon;
  final String title;
  final String body;
  final Widget? trailing;

  const _StatusCard({
    required this.icon,
    required this.title,
    required this.body,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 40),
        Center(child: icon),
        const SizedBox(height: 24),
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          body,
          style: const TextStyle(fontSize: 15, height: 1.5),
          textAlign: TextAlign.center,
        ),
        if (trailing != null) ...[
          const SizedBox(height: 32),
          trailing!,
        ],
      ],
    );
  }
}
