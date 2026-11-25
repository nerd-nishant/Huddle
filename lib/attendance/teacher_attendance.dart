import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// Teacher home for attendance: only subjects assigned to this teacher appear
/// (enforced by RLS + the start_session RPC, not just by this list).
class TeacherAttendanceScreen extends StatefulWidget {
  final Profile me;
  const TeacherAttendanceScreen({super.key, required this.me});
  @override
  State<TeacherAttendanceScreen> createState() => _TeacherAttendanceScreenState();
}

class _TeacherAttendanceScreenState extends State<TeacherAttendanceScreen> {
  late Future<List<dynamic>> f = _load();
  Future<List<dynamic>> _load() => sb
      .from('teacher_assignments')
      .select('class_label, subjects(id,name,code,semester)')
      .eq('teacher_id', widget.me.id);
  void _reload() => setState(() => f = _load());

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
        future: f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const SkeletonList(count: 3);
          if (snap.hasError) return ErrorState(error: snap.error!, onRetry: _reload);
          final rows = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
              const Text('Attendance',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -.5)),
              const SizedBox(height: 4),
              const Text('Pick a subject to start a lecture'),
              const SizedBox(height: 14),
              if (rows.isEmpty)
                const EmptyState(
                    icon: Icons.assignment_ind_rounded,
                    title: 'No subjects assigned',
                    subtitle: 'Your institution assigns subjects to you. Pull to refresh once done.')
              else
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                              gradient: HC.grad, borderRadius: BorderRadius.circular(16)),
                          child: const Icon(Icons.menu_book_rounded, color: Colors.white),
                        ),
                        title: Text(r['subjects']['name'],
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        subtitle: Text(
                            '${r['subjects']['code']} · Sem ${r['subjects']['semester']}${r['class_label'] != null ? ' · ${r['class_label']}' : ''}'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => SubjectSessions(
                                    subject: Map<String, dynamic>.from(r['subjects'])))),
                      ),
                    ),
                  ),
            ]),
          );
        },
      );
}

class SubjectSessions extends StatefulWidget {
  final Map<String, dynamic> subject;
  const SubjectSessions({super.key, required this.subject});
  @override
  State<SubjectSessions> createState() => _SubjectSessionsState();
}

class _SubjectSessionsState extends State<SubjectSessions> {
  late Future<List<dynamic>> f = _load();
  bool starting = false;

  Future<List<dynamic>> _load() => sb
      .from('attendance_sessions')
      .select('id,title,status,created_at')
      .eq('subject_id', widget.subject['id'])
      .order('created_at', ascending: false);

  Future<void> _start() async {
    final title = TextEditingController(text: 'Lecture');
    double radius = 80;
    final go = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('New lecture',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            TextField(
                controller: title,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Lecture title', counterText: '')),
            const SizedBox(height: 14),
            Text('Allowed distance from you: ${radius.round()} m',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            Slider(
                value: radius,
                min: 30,
                max: 300,
                divisions: 27,
                onChanged: (v) => set(() => radius = v)),
            const Text(
                'Students must scan the live QR while within this distance of your current location.',
                style: TextStyle(fontSize: 12.5)),
            const SizedBox(height: 18),
            FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.qr_code_2_rounded),
                label: const Text('Start & show QR')),
          ]),
        ),
      ),
    );
    if (go != true) return;
    setState(() => starting = true);
    try {
      final pos = await getPosition();
      final id = await sb.rpc('start_session', params: {
        'p_subject': widget.subject['id'],
        'p_title': title.text,
        'p_lat': pos.latitude,
        'p_lng': pos.longitude,
        'p_radius': radius.round(),
      });
      if (!mounted) return;
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => SessionScreen(
                  sessionId: id as String, subject: widget.subject, title: title.text)));
      setState(() => f = _load());
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.subject['name'])),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          FilledButton.icon(
            onPressed: starting ? null : _start,
            icon: starting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.qr_code_2_rounded),
            label: const Text('Start lecture (QR + location)'),
          ),
          const SectionTitle('Past lectures'),
          FutureBuilder<List<dynamic>>(
            future: f,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Column(children: const [Skeleton(), Skeleton()]);
              }
              if (snap.hasError) {
                return ErrorState(error: snap.error!, onRetry: () => setState(() => f = _load()));
              }
              final rows = snap.data!;
              if (rows.isEmpty) {
                return const EmptyState(
                    icon: Icons.history_rounded, title: 'No lectures yet');
              }
              return Column(children: [
                for (final s in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        title: Text(s['title'], style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(
                            '${fmtDate(DateTime.parse(s['created_at']).toLocal())} · ${fmtTime(DateTime.parse(s['created_at']))}'),
                        trailing: s['status'] == 'open'
                            ? const Pill('LIVE', color: HC.lime)
                            : const Pill('SUBMITTED', color: HC.violetSoft),
                        onTap: () async {
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => SessionScreen(
                                      sessionId: s['id'],
                                      subject: widget.subject,
                                      title: s['title'])));
                          setState(() => f = _load());
                        },
                      ),
                    ),
                  ),
              ]);
            },
          ),
        ]),
      );
}

/// Live lecture: rotating QR + roster with manual present/absent + submit.
class SessionScreen extends StatefulWidget {
  final String sessionId, title;
  final Map<String, dynamic> subject;
  const SessionScreen(
      {super.key, required this.sessionId, required this.subject, required this.title});
  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  bool loading = true, open = true, closing = false;
  Object? error;
  List<Map<String, dynamic>> roster = [];
  final Map<String, String> status = {}; // student_id -> present/absent
  String? token;
  Timer? rotator;
  RealtimeChannel? ch;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    rotator?.cancel();
    if (ch != null) sb.removeChannel(ch!);
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final s = await sb.from('attendance_sessions').select('status').eq('id', widget.sessionId).single();
      open = s['status'] == 'open';
      final r = await sb
          .from('enrollments')
          .select('student_id, profiles(username,full_name,avatar_url)')
          .eq('subject_id', widget.subject['id']);
      roster = List<Map<String, dynamic>>.from(r)
        ..sort((a, b) => (a['profiles']['username'] as String).compareTo(b['profiles']['username']));
      await _loadRecords();
      ch = sb
          .channel('session-${widget.sessionId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'attendance_records',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'session_id',
                value: widget.sessionId),
            callback: (_) => _loadRecords(),
          )
          .subscribe();
      if (open) await _rotate();
      rotator = Timer.periodic(const Duration(seconds: 20), (_) => _rotate());
    } catch (e) {
      error = e;
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _rotate() async {
    if (!open) return;
    try {
      final t = await sb.rpc('rotate_session_token', params: {'p_session': widget.sessionId});
      if (mounted) setState(() => token = t as String);
    } catch (_) {}
  }

  Future<void> _loadRecords() async {
    final r = await sb
        .from('attendance_records')
        .select('student_id,status')
        .eq('session_id', widget.sessionId);
    if (!mounted) return;
    setState(() {
      status
        ..clear()
        ..addEntries(r.map((e) => MapEntry(e['student_id'] as String, e['status'] as String)));
    });
  }

  Future<void> _mark(String student, String st) async {
    final old = status[student];
    setState(() => status[student] = st);
    try {
      await sb.from('attendance_records').upsert({
        'session_id': widget.sessionId,
        'student_id': student,
        'status': st,
        'method': 'manual',
      }, onConflict: 'session_id,student_id');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (old == null) { status.remove(student); } else { status[student] = old; }
      });
      toast(context, errText(e), error: true);
    }
  }

  Future<void> _submit() async {
    final unmarked = roster.where((r) => !status.containsKey(r['student_id'])).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit attendance?'),
        content: Text(
            'This closes the lecture and publishes it to students.${unmarked > 0 ? '\n\n$unmarked student(s) with no mark will be recorded absent.' : ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Submit')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => closing = true);
    try {
      await sb.rpc('close_session', params: {'p_session': widget.sessionId});
      rotator?.cancel();
      await _loadRecords();
      if (mounted) {
        setState(() { open = false; token = null; });
        toast(context, 'Attendance submitted ✓');
      }
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => closing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (error != null) {
      return Scaffold(
          appBar: AppBar(),
          body: ErrorState(error: error!, onRetry: () { setState(() { loading = true; error = null; }); _init(); }));
    }
    final present = status.values.where((s) => s == 'present').length;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      bottomNavigationBar: open
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: closing ? null : _submit,
                  icon: const Icon(Icons.send_rounded),
                  label: Text(closing ? 'Submitting...' : 'Submit attendance'),
                ),
              ),
            )
          : null,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        if (open)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(gradient: HC.grad, borderRadius: BorderRadius.circular(30)),
            child: Column(children: [
              const Text('Scan with HUDDLE to mark present',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
                child: token == null
                    ? const SizedBox(
                        width: 230, height: 230, child: Center(child: CircularProgressIndicator()))
                    : QrImageView(
                        data: 'huddle://att?s=${widget.sessionId}&t=$token',
                        size: 230,
                        backgroundColor: Colors.white,
                      ),
              ),
              const SizedBox(height: 12),
              const Text('Code refreshes every 20 s · location is checked on the student\'s phone',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          )
        else
          const Pill('Submitted - edits are logged', color: HC.lime, icon: Icons.verified_rounded),
        SectionTitle('Roster · $present / ${roster.length} present'),
        if (roster.isEmpty)
          const EmptyState(
              icon: Icons.people_outline_rounded,
              title: 'No students enrolled',
              subtitle: 'Students appear here once enrolled in this subject.')
        else
          for (final r in roster)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(children: [
                    Avatar(name: r['profiles']['username'], url: r['profiles']['avatar_url'], radius: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r['profiles']['full_name'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('@${r['profiles']['username']}', style: const TextStyle(fontSize: 12.5)),
                      ]),
                    ),
                    _mark2(r['student_id'], 'present', 'P', HC.lime),
                    const SizedBox(width: 6),
                    _mark2(r['student_id'], 'absent', 'A', HC.pink),
                  ]),
                ),
              ),
            ),
      ]),
    );
  }

  Widget _mark2(String id, String st, String label, Color c) {
    final sel = status[id] == st;
    return GestureDetector(
      onTap: () => _mark(id, st),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? c : c.withOpacity(.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(label,
            style: TextStyle(
                color: sel ? HC.ink : c, fontWeight: FontWeight.w900, fontSize: 16)),
      ),
    );
  }
}
