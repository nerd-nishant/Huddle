import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'chat_room.dart';

Color _hex(String? h) {
  try {
    return Color(int.parse('FF${(h ?? '#8B5CF6').replaceAll('#', '')}', radix: 16));
  } catch (_) {
    return HC.violet;
  }
}

String _range(Map<String, dynamic> f) {
  if (f['starts_on'] == null) return 'Dates soon';
  final a = DateTime.parse(f['starts_on']);
  final b = f['ends_on'] == null ? null : DateTime.parse(f['ends_on']);
  return b == null || b == a ? fmtDate(a) : '${fmtDate(a)} - ${fmtDate(b)}';
}

class FestCard extends StatelessWidget {
  final Map<String, dynamic> fest;
  final Profile me;
  final double? width;
  const FestCard({super.key, required this.fest, required this.me, this.width});

  @override
  Widget build(BuildContext context) {
    final c = _hex(fest['color']);
    return GestureDetector(
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => FestScreen(fest: fest, me: me))),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: LinearGradient(
              colors: [c, c.withOpacity(.45), HC.pink.withOpacity(.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: Colors.black26, borderRadius: BorderRadius.circular(20)),
                child: Text(_range(fest),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(fest['name'],
                    style: const TextStyle(
                        color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, height: 1.05)),
                if (fest['tagline'] != null)
                  Text(fest['tagline'],
                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
              ]),
            ]),
      ),
    );
  }
}

class FestsTab extends StatefulWidget {
  final Profile me;
  const FestsTab({super.key, required this.me});
  @override
  State<FestsTab> createState() => _FestsTabState();
}

class _FestsTabState extends State<FestsTab> {
  late Future<List<dynamic>> f = sb.from('fests').select().order('starts_on');
  void _reload() => setState(() => f = sb.from('fests').select().order('starts_on'));

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
        future: f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const SkeletonList(count: 3);
          if (snap.hasError) return ErrorState(error: snap.error!, onRetry: _reload);
          final fests = snap.data!;
          if (fests.isEmpty) {
            return const EmptyState(
                icon: Icons.celebration_rounded,
                title: 'No fests yet',
                subtitle: 'Fest channels appear here when your college announces one.');
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: fests.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (_, i) => SizedBox(
                  height: 170,
                  child: FestCard(fest: Map<String, dynamic>.from(fests[i]), me: widget.me)),
            ),
          );
        },
      );
}

/// A fest has its own Announcements channel and a Discussion channel, kept
/// completely separate from academic groups.
class FestScreen extends StatefulWidget {
  final Map<String, dynamic> fest;
  final Profile me;
  const FestScreen({super.key, required this.fest, required this.me});
  @override
  State<FestScreen> createState() => _FestScreenState();
}

class _FestScreenState extends State<FestScreen> {
  List<Map<String, dynamic>> groups = [];
  Set<String> joined = {};
  bool loading = true, joining = false;
  Object? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final g = await sb.from('groups').select().eq('fest_id', widget.fest['id']);
      final m = await sb.from('group_members').select('group_id').eq('user_id', widget.me.id);
      groups = List<Map<String, dynamic>>.from(g);
      joined = m.map((e) => e['group_id'] as String).toSet();
    } catch (e) {
      error = e;
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _join() async {
    setState(() => joining = true);
    try {
      await sb.from('group_members').upsert([
        for (final g in groups) {'group_id': g['id'], 'user_id': widget.me.id}
      ], ignoreDuplicates: true);
      await _load();
      if (mounted) toast(context, 'You\'re in! 🎉');
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fest = widget.fest;
    final c = _hex(fest['color']);
    final announce = groups.where((g) => g['kind'] == 'fest_announce').toList();
    final chat = groups.where((g) => g['kind'] == 'fest_chat').toList();
    final isIn = groups.isNotEmpty && groups.every((g) => joined.contains(g['id']));

    return Scaffold(
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? SafeArea(child: ErrorState(error: error!, onRetry: _load))
              : DefaultTabController(
                  length: 3,
                  child: NestedScrollView(
                    headerSliverBuilder: (_, __) => [
                      SliverAppBar(
                        pinned: true,
                        expandedHeight: 220,
                        flexibleSpace: FlexibleSpaceBar(
                          background: Container(
                            padding: const EdgeInsets.fromLTRB(22, 90, 22, 70),
                            decoration: BoxDecoration(
                                gradient: LinearGradient(
                                    colors: [c, HC.pink],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(fest['name'],
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 34,
                                          fontWeight: FontWeight.w900,
                                          height: 1)),
                                  const SizedBox(height: 6),
                                  Text('${_range(fest)}  ·  ${fest['tagline'] ?? ''}',
                                      style: const TextStyle(
                                          color: Colors.white, fontWeight: FontWeight.w700)),
                                ]),
                          ),
                        ),
                        bottom: const TabBar(
                          tabs: [Tab(text: 'About'), Tab(text: 'Announcements'), Tab(text: 'Chat')],
                        ),
                      ),
                    ],
                    body: TabBarView(children: [
                      ListView(padding: const EdgeInsets.all(20), children: [
                        Text(fest['description'] ?? 'Details coming soon.',
                            style: const TextStyle(fontSize: 16, height: 1.5)),
                        const SizedBox(height: 24),
                        if (!isIn)
                          FilledButton.icon(
                            onPressed: joining ? null : _join,
                            icon: const Icon(Icons.celebration_rounded),
                            label: Text(joining ? 'Joining...' : 'Join fest channels'),
                          )
                        else
                          const Pill('You\'re in the fest channels',
                              color: HC.lime, icon: Icons.check_circle_rounded),
                      ]),
                      announce.isEmpty
                          ? const EmptyState(icon: Icons.campaign_rounded, title: 'No channel')
                          : ChatRoom(group: announce.first, embedded: true),
                      chat.isEmpty
                          ? const EmptyState(icon: Icons.forum_rounded, title: 'No channel')
                          : ChatRoom(group: chat.first, embedded: true),
                    ]),
                  ),
                ),
    );
  }
}
