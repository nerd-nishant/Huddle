import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'scan_screen.dart';

/// Student dashboard. Read-only: students have no write access to attendance
/// tables at all; the only way to mark yourself present is the QR + location RPC.
class StudentAttendanceScreen extends StatefulWidget {
  final Profile me;
  const StudentAttendanceScreen({super.key, required this.me});
  @override
  State<StudentAttendanceScreen> createState() => _StudentAttendanceScreenState();
}

class _StudentAttendanceScreenState extends State<StudentAttendanceScreen> {
  late Future<List<dynamic>> f = _load();
  RealtimeChannel? ch;

  Future<List<dynamic>> _load() => sb.from('attendance_summary').select().order('subject_name');

  @override
  void initState() {
    super.initState();
    // Real-time: refresh whenever one of MY attendance rows changes.
    ch = sb
        .channel('my-attendance-${widget.me.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'attendance_records',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'student_id',
              value: widget.me.id),
          callback: (_) {
            if (mounted) setState(() => f = _load());
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (ch != null) sb.removeChannel(ch!);
    super.dispose();
  }

  void _reload() => setState(() => f = _load());

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: HC.lime,
          foregroundColor: HC.ink,
          onPressed: () async {
            await Navigator.push(
                context, MaterialPageRoute(builder: (_) => const ScanScreen()));
            _reload();
          },
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Scan to mark', style: TextStyle(fontWeight: FontWeight.w900)),
        ),
        body: FutureBuilder<List<dynamic>>(
          future: f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const SkeletonList(count: 4);
            if (snap.hasError) return ErrorState(error: snap.error!, onRetry: _reload);
            final rows = snap.data!;
            int total = 0, att = 0;
            for (final r in rows) {
              total += r['total'] as int;
              att += r['attended'] as int;
            }
            final pct = total == 0 ? null : att * 100 / total;
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 100), children: [
                const Text('Attendance',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -.5)),
                const SizedBox(height: 14),
                _overall(pct, total, att),
                const SectionTitle('Subject-wise'),
                if (rows.isEmpty)
                  const EmptyState(
                      icon: Icons.menu_book_rounded,
                      title: 'No subjects yet',
                      subtitle: 'You\'ll see subjects once you\'re enrolled for this semester.')
                else
                  for (final r in rows)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _SubjectCard(row: Map<String, dynamic>.from(r))),
              ]),
            );
          },
        ),
      );

  Widget _overall(double? pct, int total, int att) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(gradient: HC.grad, borderRadius: BorderRadius.circular(30)),
        child: Row(children: [
          _Ring(pct: pct, size: 112, stroke: 11, color: Colors.white, track: Colors.white24, big: true),
          const SizedBox(width: 22),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _stat('Total classes', '$total'),
              _stat('Attended', '$att'),
              _stat('Missed', '${total - att}'),
            ]),
          ),
        ]),
      );

  Widget _stat(String l, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(l, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600))),
          Text(v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
        ]),
      );
}

Color pctColor(double? p) =>
    p == null ? HC.violetSoft : p >= 85 ? HC.lime : p >= 75 ? HC.sky : p >= 60 ? HC.peach : HC.pink;

class _SubjectCard extends StatelessWidget {
  final Map<String, dynamic> row;
  const _SubjectCard({required this.row});
  @override
  Widget build(BuildContext context) {
    final total = row['total'] as int, att = row['attended'] as int, missed = row['missed'] as int;
    final pct = total == 0 ? null : att * 100 / total;
    final c = pctColor(pct);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          _Ring(pct: pct, size: 64, stroke: 7, color: c, track: c.withOpacity(.18)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(row['subject_name'],
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(row['subject_code'],
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(.55))),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                Pill('$total classes', color: HC.violetSoft),
                Pill('$att attended', color: HC.lime),
                Pill('$missed missed', color: HC.pink),
              ]),
              if (pct != null && pct < 75)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Below 75% - at risk',
                      style: TextStyle(color: HC.pink, fontWeight: FontWeight.w800, fontSize: 12.5)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  final double? pct, size, stroke;
  final Color color, track;
  final bool big;
  const _Ring({
    required this.pct,
    required double this.size,
    required double this.stroke,
    required this.color,
    required this.track,
    this.big = false,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          CustomPaint(
              size: Size.square(size!),
              painter: _RingPainter((pct ?? 0) / 100, stroke!, color, track)),
          Text(pct == null ? '--' : '${pct!.toStringAsFixed(0)}%',
              style: TextStyle(
                  color: big ? Colors.white : color,
                  fontWeight: FontWeight.w900,
                  fontSize: big ? 26 : 15)),
        ]),
      );
}

class _RingPainter extends CustomPainter {
  final double v, w;
  final Color c, t;
  _RingPainter(this.v, this.w, this.c, this.t);
  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromLTWH(w / 2, w / 2, s.width - w, s.height - w);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, math.pi * 2, false, p..color = t);
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * v.clamp(0, 1), false, p..color = c);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.c != c;
}
