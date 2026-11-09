import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/reservation_service.dart';
import '../../theme.dart';
import '../../widgets/form_field.dart';

/// Confirms a pickup: the driver types the passenger's four digits, or scans their QR.
///
/// Pops `true` once the API accepts the code. Three wrong codes lock check-in for good, so the
/// server's own wording ("2 tries left", "locked") is shown rather than a guess at the count.
class CheckInDialog extends StatefulWidget {
  const CheckInDialog({
    super.key,
    required this.reservationId,
    required this.passengerName,
  });

  final String reservationId;
  final String passengerName;

  @override
  State<CheckInDialog> createState() => _CheckInDialogState();
}

class _CheckInDialogState extends State<CheckInDialog> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();

  bool _sending = false;
  bool _locked = false;
  String? _message;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit([String? scanned]) async {
    if (scanned == null && !_formKey.currentState!.validate()) return;
    final code = (scanned ?? _code.text).trim();
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      await ReservationService.instance.checkIn(widget.reservationId, code);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        // The API counts the attempts, so its message is the accurate one.
        _message = authErrorMessage(error);
        _locked = error is ApiException && error.code == 'pickup_code_locked';
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _scan() async {
    final scanned = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const _ScanCodePage()));
    if (scanned == null || !mounted) return;
    // The QR holds the four digits themselves, so it goes straight to the API.
    _code.text = scanned;
    await _submit(scanned);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Check in ${widget.passengerName}'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Ask for the four digits on their screen, or scan the QR.',
            style: TextStyle(color: carShareMuted, height: 1.3),
          ),
          const SizedBox(height: 14),
          CarShareTextField(
            controller: _code,
            label: 'Pickup code',
            icon: Icons.pin_outlined,
            keyboardType: TextInputType.number,
            validator: (value) {
              final text = (value ?? '').trim();
              if (text.length != 4 || int.tryParse(text) == null) {
                return 'The code is four digits.';
              }
              return null;
            },
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _sending || _locked ? null : _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan the QR instead'),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 6),
            Text(
              _message!,
              style: TextStyle(
                fontSize: 13,
                height: 1.3,
                color: _locked ? carShareDanger : carShareWarning,
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Close'),
      ),
      FilledButton(
        onPressed: _sending || _locked ? null : () => _submit(),
        child: _sending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Confirm'),
      ),
    ],
  );
}

/// A camera viewfinder that pops the first four-digit code it reads.
class _ScanCodePage extends StatefulWidget {
  const _ScanCodePage();

  @override
  State<_ScanCodePage> createState() => _ScanCodePageState();
}

class _ScanCodePageState extends State<_ScanCodePage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      // Only a pickup code is interesting; any other QR in shot is ignored.
      if (value != null && value.length == 4 && int.tryParse(value) != null) {
        _handled = true;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: const Text(
        'Scan the pickup QR',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    body: Stack(
      children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: carShareGreen, width: 3),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        const Positioned(
          left: 24,
          right: 24,
          bottom: 48,
          child: Text(
            'Point the camera at the code on the passenger’s screen.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
        ),
      ],
    ),
  );
}
