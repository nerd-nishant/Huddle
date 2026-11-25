import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// Scans the teacher's rotating QR and marks the student present.
///
/// Only a `huddle://att?...` code is accepted, and the SERVER (mark_attendance_qr)
/// independently checks: signed-in student, enrolled, session open, token fresh,
/// and GPS within the classroom radius. A photo of the QR sent to a friend fails
/// because the token rotates every ~20 s and the friend must also be on campus.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates, formats: [BarcodeFormat.qrCode]);
  bool busy = false;
  String status = 'Point at the QR on your teacher\'s screen';
  bool? ok;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture cap) async {
    if (busy || ok == true) return;
    final raw = cap.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'huddle' || uri.host != 'att') {
      setState(() => status = 'That\'s not a HUDDLE attendance code');
      return;
    }
    final session = uri.queryParameters['s'], token = uri.queryParameters['t'];
    if (session == null || token == null) return;

    setState(() { busy = true; status = 'Checking your location...'; });
    try {
      final pos = await getPosition(rejectMock: true);
      setState(() => status = 'Marking you present...');
      final res = await sb.rpc('mark_attendance_qr', params: {
        'p_session': session,
        'p_token': token,
        'p_lat': pos.latitude,
        'p_lng': pos.longitude,
      });
      setState(() {
        ok = true;
        status = 'You\'re marked present ✓  (${res['distance_m']} m from class)';
      });
      await Future.delayed(const Duration(milliseconds: 1600));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        ok = false;
        status = errText(e);
        busy = false;
      });
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) setState(() { ok = null; status = 'Point at the QR on your teacher\'s screen'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ok == true ? HC.lime : ok == false ? HC.pink : Colors.white;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        MobileScanner(controller: controller, onDetect: _onDetect),
        // viewfinder
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: c, width: 4),
              borderRadius: BorderRadius.circular(32),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              IconButton.filledTonal(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded)),
              const Spacer(),
              IconButton.filledTonal(
                  onPressed: controller.toggleTorch,
                  icon: const Icon(Icons.flashlight_on_rounded)),
            ]),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 40,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: HC.card.withOpacity(.92), borderRadius: BorderRadius.circular(24)),
            child: Row(children: [
              if (busy)
                const Padding(
                    padding: EdgeInsets.only(right: 14),
                    child: SizedBox(
                        width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)))
              else
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Icon(
                      ok == true
                          ? Icons.check_circle_rounded
                          : ok == false
                              ? Icons.error_rounded
                              : Icons.location_on_rounded,
                      color: c),
                ),
              Expanded(
                  child: Text(status,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700, height: 1.3))),
            ]),
          ),
        ),
      ]),
    );
  }
}
