import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../chats/chats_screen.dart';
import '../chats/fests.dart';
import '../attendance/attendance_screen.dart';
import '../attendance/teacher_attendance.dart';
import '../updates/updates_screen.dart';
import '../study/study_screen.dart';

class Shell extends StatefulWidget {
  final Profile me;
  const Shell({super.key, required this.me});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int idx = 0;
  late final List<Widget> pages;

  @override
  void initState() {
    super.initState();
    // Put the user into the groups/subjects that match their profile.
    sb.rpc('claim_my_groups').catchError((_) {});
    final me = widget.me;
    pages = [
      HomeScreen(me: me, onGo: (i) => setState(() => idx = i)),
      ChatsScreen(me: me),
      me.isTeacher
          ? TeacherAttendanceScreen(me: me)
          : me.isStudent
              ? StudentAttendanceScreen(me: me)
              : const EmptyState(
                  icon: Icons.lock_outline_rounded,
                  title: 'Not available for institution accounts'),
      UpdatesScreen(me: me),
      const StudyScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            const ConnectivityBanner(),
            Expanded(child: IndexedStack(index: idx, children: pages)),
          ]),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: idx,
          onDestinationSelected: (i) => setState(() => idx = i),
          destinations: [
            const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Home'),
            const NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline_rounded),
                selectedIcon: Icon(Icons.chat_bubble_rounded),
                label: 'Chats'),
            NavigationDestination(
                icon: Icon(widget.me.isTeacher
                    ? Icons.fact_check_outlined
                    : Icons.qr_code_scanner_rounded),
                selectedIcon: Icon(widget.me.isTeacher
                    ? Icons.fact_check_rounded
                    : Icons.qr_code_scanner_rounded),
                label: 'Attendance'),
            const NavigationDestination(
                icon: Icon(Icons.campaign_outlined),
                selectedIcon: Icon(Icons.campaign_rounded),
                label: 'Updates'),
            const NavigationDestination(
                icon: Icon(Icons.auto_stories_outlined),
                selectedIcon: Icon(Icons.auto_stories_rounded),
                label: 'Study'),
          ],
        ),
      );
}

// ============================================================================
class HomeScreen extends StatefulWidget {
  final Profile me;
  final void Function(int) onGo;
  const HomeScreen({super.key, required this.me, required this.onGo});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<Map<String, dynamic>> f = _load();

  Future<Map<String, dynamic>> _load() async {
    final me = widget.me;
    final updates = await sb
        .from('updates')
        .select('id,title,category,created_at')
        .eq('kind', 'official')
        .order('created_at', ascending: false)
        .limit(3);
    final fests = await sb.from('fests').select().order('starts_on').limit(6);
    double? pct;
    int subjects = 0;
    if (me.isStudent) {
      final a = await sb.from('attendance_summary').select();
      int t = 0, p = 0;
      for (final r in a) {
        t += (r['total'] as int);
        p += (r['attended'] as int);
      }
      pct = t == 0 ? null : p * 100 / t;
    } else if (me.isTeacher) {
      final a = await sb.from('teacher_assignments').select('subject_id').eq('teacher_id', me.id);
      subjects = a.length;
    }
    return {'updates': updates, 'fests': fests, 'pct': pct, 'subjects': subjects};
  }

  void _reload() => setState(() => f = _load());

  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    final cs = Theme.of(context).colorScheme;
    final hour = DateTime.now().hour;
    final hi = hour < 12 ? 'morning' : hour < 17 ? 'afternoon' : 'evening';
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('good $hi,',
                  style: TextStyle(color: cs.onSurface.withOpacity(.6), fontWeight: FontWeight.w600)),
              Text(me.fullName.isEmpty ? '@${me.username}' : me.fullName.split(' ').first,
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -.5)),
            ]),
          ),
          GestureDetector(
            onTap: () => showModalBottomSheet(
                context: context,
                showDragHandle: true,
                isScrollControlled: true,
                builder: (_) => ProfileSheet(me: me)),
            child: Container(
              padding: const EdgeInsets.all(2.5),
              decoration: const BoxDecoration(gradient: HC.grad, shape: BoxShape.circle),
              child: Avatar(name: me.username, url: me.avatarUrl, radius: 24),
            ),
          ),
        ]),
        const SizedBox(height: 18),
        FutureBuilder<Map<String, dynamic>>(
          future: f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return Column(children: const [Skeleton(height: 130), Skeleton(), Skeleton()]);
            }
            if (snap.hasError) return ErrorState(error: snap.error!, onRetry: _reload);
            final d = snap.data!;
            final pct = d['pct'] as double?;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _hero(me, pct, d['subjects'] as int),
              const SizedBox(height: 12),
              Row(children: [
                _quick(Icons.chat_bubble_rounded, 'Chats', HC.sky, () => widget.onGo(1)),
                const SizedBox(width: 10),
                _quick(Icons.campaign_rounded, 'Updates', HC.peach, () => widget.onGo(3)),
                const SizedBox(width: 10),
                _quick(Icons.auto_stories_rounded, 'Notes', HC.lime, () => widget.onGo(4)),
              ]),
              const SectionTitle('Fests happening'),
              SizedBox(
                height: 150,
                child: (d['fests'] as List).isEmpty
                    ? const EmptyState(icon: Icons.celebration_rounded, title: 'No fests yet')
                    : ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final fe in d['fests'] as List)
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: FestCard(
                                  fest: Map<String, dynamic>.from(fe),
                                  me: me,
                                  width: 260),
                            ),
                        ],
                      ),
              ),
              SectionTitle('Official updates',
                  trailing: TextButton(onPressed: () => widget.onGo(3), child: const Text('See all'))),
              if ((d['updates'] as List).isEmpty)
                const Padding(
                    padding: EdgeInsets.all(12), child: Text('Nothing official yet.'))
              else
                for (final u in d['updates'] as List)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        leading: const Icon(Icons.verified_rounded, color: HC.sky),
                        title: Text(u['title'],
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${u['category']} · ${ago(DateTime.parse(u['created_at']))}'),
                        onTap: () => widget.onGo(3),
                      ),
                    ),
                  ),
            ]);
          },
        ),
      ]),
    );
  }

  Widget _hero(Profile me, double? pct, int subjects) {
    if (me.isStudent) {
      final low = pct != null && pct < 75;
      return GestureDetector(
        onTap: () => widget.onGo(2),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(gradient: HC.grad, borderRadius: BorderRadius.circular(28)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Attendance',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(pct == null ? '--' : '${pct.toStringAsFixed(0)}%',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 46, fontWeight: FontWeight.w900, height: 1)),
                const SizedBox(height: 8),
                Text(
                    pct == null
                        ? 'No lectures recorded yet'
                        : low
                            ? 'Below 75% - attend more lectures'
                            : 'You\'re on track',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ]),
            ),
            Container(
              width: 62,
              height: 62,
              decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
              child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 30),
            ),
          ]),
        ),
      );
    }
    if (me.isTeacher) {
      return GestureDetector(
        onTap: () => widget.onGo(2),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(gradient: HC.grad, borderRadius: BorderRadius.circular(28)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Take attendance',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text('$subjects assigned subject${subjects == 1 ? '' : 's'} · QR + location',
                    style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
              ]),
            ),
            const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 30),
          ]),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(gradient: HC.grad, borderRadius: BorderRadius.circular(28)),
      child: const Text('Institution account\nPublish official updates from the Updates tab.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
    );
  }

  Widget _quick(IconData i, String t, Color c, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(22)),
            child: Column(children: [
              Icon(i, color: c, size: 28),
              const SizedBox(height: 8),
              Text(t, style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      );
}

// ============================================================================
class ProfileSheet extends StatefulWidget {
  final Profile me;
  const ProfileSheet({super.key, required this.me});
  @override
  State<ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<ProfileSheet> {
  String? url;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    url = widget.me.avatarUrl;
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final f = r?.files.single;
    if (f == null || f.bytes == null) return;
    if (f.size > 3 * 1024 * 1024) {
      toast(context, 'Pick an image under 3 MB', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      final ext = (f.extension ?? 'jpg').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final path = '${widget.me.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await sb.storage.from('avatars').uploadBinary(path, f.bytes!);
      final pub = sb.storage.from('avatars').getPublicUrl(path);
      await sb.from('profiles').update({'avatar_url': pub}).eq('id', widget.me.id);
      setState(() => url = pub);
      if (mounted) toast(context, 'Profile picture updated');
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onTap: busy ? null : _pick,
          child: Stack(alignment: Alignment.bottomRight, children: [
            Avatar(name: me.username, url: url, radius: 46),
            CircleAvatar(
                radius: 15,
                backgroundColor: HC.violet,
                child: busy
                    ? const SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.edit_rounded, size: 15, color: Colors.white)),
          ]),
        ),
        const SizedBox(height: 14),
        Text(me.fullName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        Text('@${me.username}'),
        const SizedBox(height: 8),
        Pill(me.role.toUpperCase(), color: HC.lime),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16)),
          child: const Row(children: [
            Icon(Icons.shield_rounded, color: HC.sky),
            SizedBox(width: 12),
            Expanded(
                child: Text('Your phone number and email are never shown to other students.',
                    style: TextStyle(fontWeight: FontWeight.w600))),
          ]),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: () {
            Navigator.pop(context);
            sb.auth.signOut();
          },
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sign out'),
        ),
      ]),
    );
  }
}
