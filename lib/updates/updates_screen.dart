import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// Official = verified, publishable only by institution accounts (RLS-enforced).
/// Unofficial = student posts, always labelled unverified.
class UpdatesScreen extends StatefulWidget {
  final Profile me;
  const UpdatesScreen({super.key, required this.me});
  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> with SingleTickerProviderStateMixin {
  late final TabController tc = TabController(length: 2, vsync: this)
    ..addListener(() => setState(() {}));

  bool get officialTab => tc.index == 0;
  bool get canCompose => officialTab ? widget.me.isInstitution : !widget.me.isInstitution;

  @override
  void dispose() {
    tc.dispose();
    super.dispose();
  }

  Future<void> _compose() async {
    final official = officialTab;
    final title = TextEditingController(), body = TextEditingController();
    final cats = official
        ? ['Notice', 'Exam', 'Academic', 'Event', 'Admission']
        : ['Info', 'Event', 'Lost & Found', 'Doubt', 'Other'];
    String cat = cats.first;
    final key = GlobalKey<FormState>();
    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Form(
            key: key,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(official ? 'Publish official notice' : 'Post a student update',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              if (!official)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('This will be labelled "unverified student post".',
                      style: TextStyle(color: HC.peach, fontWeight: FontWeight.w700)),
                ),
              const SizedBox(height: 14),
              Wrap(spacing: 8, children: [
                for (final c in cats)
                  ChoiceChip(label: Text(c), selected: cat == c, onSelected: (_) => set(() => cat = c)),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                controller: title,
                maxLength: 140,
                decoration: const InputDecoration(labelText: 'Title', counterText: ''),
                validator: (v) => (v ?? '').trim().length < 3 ? 'Add a title' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: body,
                maxLines: 5,
                maxLength: 5000,
                decoration: const InputDecoration(labelText: 'Details', counterText: ''),
                validator: (v) => (v ?? '').trim().length < 3 ? 'Add some details' : null,
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () async {
                  if (!key.currentState!.validate()) return;
                  try {
                    await sb.from('updates').insert({
                      'kind': official ? 'official' : 'unofficial',
                      'category': cat,
                      'title': title.text.trim(),
                      'body': body.text.trim(),
                      'college_id': widget.me.collegeId,
                    });
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    if (ctx.mounted) toast(ctx, errText(e), error: true);
                  }
                },
                child: const Text('Post'),
              ),
            ]),
          ),
        ),
      ),
    );
    if (posted == true && mounted) toast(context, 'Posted');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: canCompose
            ? FloatingActionButton.extended(
                onPressed: _compose,
                backgroundColor: HC.violet,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.edit_rounded),
                label: Text(officialTab ? 'Publish' : 'Post',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              )
            : null,
        body: Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Updates',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -.5))),
          ),
          TabBar(
            controller: tc,
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(fontWeight: FontWeight.w800),
            tabs: const [
              Tab(icon: Icon(Icons.verified_rounded, size: 18), text: 'Official', iconMargin: EdgeInsets.only(bottom: 2)),
              Tab(icon: Icon(Icons.forum_rounded, size: 18), text: 'Unofficial', iconMargin: EdgeInsets.only(bottom: 2)),
            ],
          ),
          Expanded(
            child: TabBarView(controller: tc, children: const [
              _Feed(kind: 'official'),
              _Feed(kind: 'unofficial'),
            ]),
          ),
        ]),
      );
}

class _Feed extends StatefulWidget {
  final String kind;
  const _Feed({required this.kind});
  @override
  State<_Feed> createState() => _FeedState();
}

class _FeedState extends State<_Feed> with AutomaticKeepAliveClientMixin {
  final Map<String, String> names = {};
  @override
  bool get wantKeepAlive => true;

  Future<void> _names(List<Map<String, dynamic>> rows) async {
    final need = rows.map((r) => r['author_id'] as String).where((i) => !names.containsKey(i)).toSet().toList();
    if (need.isEmpty) return;
    final r = await sb.from('profiles').select('id,username').inFilter('id', need);
    if (!mounted) return;
    setState(() { for (final p in r) { names[p['id']] = p['username']; } });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final official = widget.kind == 'official';
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: sb
          .from('updates')
          .stream(primaryKey: ['id'])
          .eq('kind', widget.kind)
          .order('created_at', ascending: false),
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(error: snap.error!, onRetry: () => setState(() {}));
        if (!snap.hasData) return const SkeletonList(count: 4);
        final rows = snap.data!;
        WidgetsBinding.instance.addPostFrameCallback((_) => _names(rows));
        if (rows.isEmpty) {
          return EmptyState(
            icon: official ? Icons.verified_rounded : Icons.forum_rounded,
            title: official ? 'No official notices yet' : 'No student posts yet',
            subtitle: official
                ? 'Verified notices from your university and college appear here.'
                : 'Be the first to share something with your campus.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _UpdateCard(
              u: rows[i], official: official, author: names[rows[i]['author_id']]),
        );
      },
    );
  }
}

class _UpdateCard extends StatelessWidget {
  final Map<String, dynamic> u;
  final bool official;
  final String? author;
  const _UpdateCard({required this.u, required this.official, this.author});

  @override
  Widget build(BuildContext context) {
    final accent = official ? HC.sky : HC.peach;
    final mine = u['author_id'] == uid;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withOpacity(.45), width: official ? 1.6 : 1),
        color: Theme.of(context).colorScheme.surfaceContainer,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          official
              ? const Pill('OFFICIAL · VERIFIED', color: HC.sky, icon: Icons.verified_rounded)
              : const Pill('STUDENT POST · UNVERIFIED', color: HC.peach, icon: Icons.warning_amber_rounded),
          const SizedBox(width: 8),
          Pill(u['category'], color: HC.violetSoft),
          const Spacer(),
          Text(ago(DateTime.parse(u['created_at'])),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(.5))),
        ]),
        const SizedBox(height: 12),
        Text(u['title'], style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.25)),
        const SizedBox(height: 6),
        Text(u['body'], style: const TextStyle(height: 1.45)),
        if (!official || mine) ...[
          const SizedBox(height: 10),
          Row(children: [
            if (!official)
              Text('by @${author ?? '...'}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
            const Spacer(),
            if (mine)
              TextButton.icon(
                onPressed: () async {
                  try {
                    await sb.from('updates').delete().eq('id', u['id']);
                  } catch (e) {
                    if (context.mounted) toast(context, errText(e), error: true);
                  }
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Delete'),
              ),
          ]),
        ],
      ]),
    );
  }
}
