import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

class InitiateResult {
  final String checkoutRequestId;
  final String paymentId;
  const InitiateResult({required this.checkoutRequestId, required this.paymentId});
}

class StatusResult {
  final String status; // PENDING | SUCCESS | FAILED | CANCELLED | TIMEOUT | EXPIRED
  final String? receiptNumber;
  final String? failureReason;
  final int? resultCode;
  const StatusResult({
    required this.status,
    this.receiptNumber,
    this.failureReason,
    this.resultCode,
  });
}

class PaymentService {
  // Your machine's LAN IP — run: ip addr (Linux) / ipconfig getifaddr en0 (macOS).
  // Do not use localhost; a physical device cannot reach it.
  static const String _baseUrl = 'http://192.168.0.101:3000';

  // Normalises to Safaricom's required 254XXXXXXXXX format.
  // Throws FormatException on unrecognised input — provider shows this as PaymentError.
  static String normalisePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');

    if (digits.startsWith('254') && digits.length == 12) return digits;
    if (digits.startsWith('0') && digits.length == 10) return '254${digits.substring(1)}';
    if (digits.startsWith('7') && digits.length == 9) return '254$digits';
    if (digits.startsWith('1') && digits.length == 9) return '254$digits';

    throw FormatException(
      'Unrecognised phone format: "$raw". '
      'Accepted: 07xx, 01xx, 7xx (9-digit), 1xx (9-digit), +254xx, 254xx.',
    );
  }

  Future<InitiateResult> initiate({
    required String phoneNumber,
    required int amount,
    required String reference,
  }) async {
    final normalised = normalisePhone(phoneNumber);
    debugPrint('[service] Initiating: $normalised KES $amount ref=$reference');

    final response = await http
        .post(
          Uri.parse('$_baseUrl/mpesa/pay'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'phoneNumber': normalised, 'amount': amount, 'reference': reference}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception('Initiation failed: ${body['error'] ?? 'Unknown server error'}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return InitiateResult(
      checkoutRequestId: data['checkoutRequestId'] as String,
      paymentId: data['paymentId'] as String,
    );
  }

  Future<StatusResult> getStatus(String checkoutRequestId) async {
    debugPrint('[service] Polling: $checkoutRequestId');

    final response = await http
        .get(Uri.parse('$_baseUrl/mpesa/status/$checkoutRequestId'))
        .timeout(const Duration(seconds: 10));

    // 404 is expected immediately after initiation — DB record not written yet.
    if (response.statusCode == 404) return const StatusResult(status: 'PENDING');
    if (response.statusCode != 200) {
      throw Exception('Status check failed: HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return StatusResult(
      status: data['status'] as String,
      receiptNumber: data['receiptNumber'] as String?,
      failureReason: data['failureReason'] as String?,
      resultCode: data['resultCode'] as int?,
    );
  }
}
