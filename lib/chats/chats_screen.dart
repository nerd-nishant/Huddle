import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'chat_room.dart';
import 'fests.dart';

const kindOrder = ['university', 'college', 'department', 'semester', 'batch', 'subject'];
const kindLabel = {
  'university': 'University',
  'college': 'College',
  'department': 'Department',
  'semester': 'Semester',
  'batch': 'Class / Batch',
  'subject': 'Subjects',
};
const kindIcon = {
  'university': Icons.account_balance_rounded,
  'college': Icons.apartment_rounded,
  'department': Icons.hub_rounded,
  'semester': Icons.event_note_rounded,
  'batch': Icons.groups_rounded,
  'subject': Icons.menu_book_rounded,
};
const kindColor = {
  'university': HC.violetSoft,
  'college': HC.sky,
  'department': HC.pink,
  'semester': HC.peach,
  'batch': HC.lime,
  'subject': HC.sky,
};

/// Chats are organised: Academic groups grouped by level, and a separate Fests tab.
class ChatsScreen extends StatelessWidget {
  final Profile me;
  const ChatsScreen({super.key, required this.me});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Row(children: [
              const Expanded(
                  child: Text('Chats',
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -.5))),
              const Pill('Private · usernames only', color: HC.lime, icon: Icons.shield_rounded),
            ]),
          ),
          const TabBar(
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: TextStyle(fontWeight: FontWeight.w800),
            tabs: [Tab(text: 'Academic'), Tab(text: 'Fests')],
          ),
          Expanded(
            child: TabBarView(children: [
              _AcademicTab(me: me),
              FestsTab(me: me),
            ]),
          ),
        ]),
      );
}

class _AcademicTab extends StatefulWidget {
  final Profile me;
  const _AcademicTab({required this.me});
  @override
  State<_AcademicTab> createState() => _AcademicTabState();
}

class _AcademicTabState extends State<_AcademicTab> {
  late Future<List<Map<String, dynamic>>> f = _load();
  String q = '';

  Future<List<Map<String, dynamic>>> _load() async {
    final r = await sb
        .from('group_members')
        .select('role, groups(id,kind,name,description,semester,announcement_only,fest_id)')
        .eq('user_id', widget.me.id);
    final out = <Map<String, dynamic>>[];
    for (final row in r) {
      final g = row['groups'];
      if (g == null || g['fest_id'] != null) continue;
      out.add({...Map<String, dynamic>.from(g), 'my_role': row['role']});
    }
    return out;
  }

  void _reload() => setState(() => f = _load());

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            onChanged: (v) => setState(() => q = v.toLowerCase()),
            decoration: const InputDecoration(
                hintText: 'Search groups',
                prefixIcon: Icon(Icons.search_rounded),
                contentPadding: EdgeInsets.symmetric(vertical: 12)),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: f,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const SkeletonList();
              if (snap.hasError) return ErrorState(error: snap.error!, onRetry: _reload);
              final groups = snap.data!
                  .where((g) => q.isEmpty || (g['name'] as String).toLowerCase().contains(q))
                  .toList();
              if (groups.isEmpty) {
                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView(children: const [
                    SizedBox(height: 80),
                    EmptyState(
                        icon: Icons.forum_rounded,
                        title: 'No groups yet',
                        subtitle:
                            'You\'ll be added to your college, department and subject groups automatically. Pull to refresh.'),
                  ]),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
                  for (final k in kindOrder)
                    if (groups.any((g) => g['kind'] == k)) ...[
                      SectionTitle(kindLabel[k]!),
                      for (final g in groups.where((g) => g['kind'] == k))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _GroupTile(group: g),
                        ),
                    ],
                ]),
              );
            },
          ),
        ),
      ]);
}

class _GroupTile extends StatelessWidget {
  final Map<String, dynamic> group;
  const _GroupTile({required this.group});
  @override
  Widget build(BuildContext context) {
    final k = group['kind'] as String;
    final c = kindColor[k] ?? HC.violet;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => ChatRoom(group: group))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                  color: c.withOpacity(.18), borderRadius: BorderRadius.circular(16)),
              child: Icon(kindIcon[k], color: c),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(group['name'],
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                if ((group['description'] ?? '').toString().isNotEmpty)
                  Text(group['description'],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(.6),
                          fontSize: 13)),
              ]),
            ),
            if (group['my_role'] == 'admin') const Pill('ADMIN', color: HC.pink),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      ),
    );
  }
}
