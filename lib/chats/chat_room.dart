import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/api.dart';
import '../core/local_db.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// A live group chat. Members are shown by username + avatar only; phone numbers
/// are not stored anywhere readable (see schema.sql).
class ChatRoom extends StatefulWidget {
  final Map<String, dynamic> group;
  /// When true, renders without its own Scaffold/AppBar (used inside fest tabs).
  final bool embedded;
  const ChatRoom({super.key, required this.group, this.embedded = false});
  @override
  State<ChatRoom> createState() => _ChatRoomState();
}

class _ChatRoomState extends State<ChatRoom> {
  final input = TextEditingController();
  final scroll = ScrollController();
  late final Stream<List<Map<String, dynamic>>> stream;
  final Map<String, Map<String, dynamic>> people = {};
  String? myRole; // null = not a member
  bool loadedRole = false, sending = false;

  String get gid => widget.group['id'];
  bool get announcementOnly => widget.group['announcement_only'] == true;
  bool get canPost => myRole != null && (!announcementOnly || myRole == 'admin');

  @override
  void initState() {
    super.initState();
    stream = sb
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('group_id', gid)
        .order('created_at', ascending: true);
    _loadRole();
  }

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _loadRole() async {
    try {
      final r = await sb
          .from('group_members')
          .select('role')
          .eq('group_id', gid)
          .eq('user_id', uid!)
          .maybeSingle();
      if (mounted) setState(() { myRole = r?['role']; loadedRole = true; });
    } catch (_) {
      if (mounted) setState(() => loadedRole = true);
    }
  }

  Future<void> _loadPeople(List<Map<String, dynamic>> msgs) async {
    final need = msgs
        .map((m) => m['sender_id'] as String)
        .where((id) => !people.containsKey(id))
        .toSet()
        .toList();
    if (need.isEmpty) return;
    final r = await sb.from('profiles').select('id,username,avatar_url').inFilter('id', need);
    if (!mounted) return;
    setState(() {
      for (final m in r) {
        people[m['id']] = Map<String, dynamic>.from(m);
      }
    });
  }

  Future<void> _send() async {
    final t = input.text.trim();
    if (t.isEmpty || sending) return;
    if (t.length > 4000) {
      toast(context, 'Message too long (max 4000 characters)', error: true);
      return;
    }
    setState(() => sending = true);
    try {
      await sb.from('messages').insert({'group_id': gid, 'body': t});
      input.clear();
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _attach() async {
    final r = await FilePicker.platform.pickFiles(withData: true);
    final f = r?.files.single;
    if (f == null || f.bytes == null) return;
    if (f.size > 15 * 1024 * 1024) {
      toast(context, 'Files must be under 15 MB', error: true);
      return;
    }
    setState(() => sending = true);
    try {
      final safe = f.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = '$gid/${DateTime.now().microsecondsSinceEpoch}_$safe';
      await sb.storage.from('study-docs').uploadBinary(path, f.bytes!);
      await sb.from('messages').insert({
        'group_id': gid,
        'attachment_path': path,
        'attachment_name': f.name,
      });
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  /// Download once, then it's available offline from the Study tab > Library.
  Future<void> _openAttachment(String remote, String name) async {
    try {
      final have = await LocalDb.findDownload(remote);
      if (have != null && File(have['local_path']).existsSync()) {
        await OpenFilex.open(have['local_path']);
        return;
      }
      toast(context, 'Downloading...');
      final bytes = await sb.storage.from('study-docs').download(remote);
      final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'study'));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}_$name'));
      await file.writeAsBytes(bytes);
      await LocalDb.addDownload(remote, name, file.path);
      if (mounted) toast(context, 'Saved for offline in Study > Library');
      await OpenFilex.open(file.path);
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
  }

  void _showMembers() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .6,
        builder: (context, sc) => FutureBuilder<List<dynamic>>(
          future: sb
              .from('group_members')
              .select('role, profiles(username,full_name,avatar_url)')
              .eq('group_id', gid),
          builder: (context, snap) {
            if (!snap.hasData) return const SkeletonList(count: 5);
            final rows = snap.data!;
            return ListView(controller: sc, padding: const EdgeInsets.all(16), children: [
              Text('${rows.length} members',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Shown by username only. Phone numbers are private.',
                  style: TextStyle(fontSize: 12.5)),
              const SizedBox(height: 10),
              for (final r in rows)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Avatar(
                      name: r['profiles']['username'], url: r['profiles']['avatar_url']),
                  title: Text('@${r['profiles']['username']}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(r['profiles']['full_name'] ?? ''),
                  trailing: r['role'] == 'admin' ? const Pill('ADMIN', color: HC.pink) : null,
                ),
            ]);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(children: [
      Expanded(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snap) {
            if (snap.hasError) {
              return ErrorState(error: snap.error!, onRetry: () => setState(() {}));
            }
            if (!snap.hasData) return const SkeletonList(count: 5);
            final msgs = snap.data!;
            WidgetsBinding.instance.addPostFrameCallback((_) => _loadPeople(msgs));
            if (msgs.isEmpty) {
              return EmptyState(
                  icon: announcementOnly ? Icons.campaign_rounded : Icons.waving_hand_rounded,
                  title: announcementOnly ? 'No announcements yet' : 'Say hi 👋',
                  subtitle: 'Messages here are only visible to group members.');
            }
            final rev = msgs.reversed.toList();
            return ListView.builder(
              controller: scroll,
              reverse: true,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              itemCount: rev.length,
              itemBuilder: (_, i) {
                final m = rev[i];
                final mine = m['sender_id'] == uid;
                final prev = i + 1 < rev.length ? rev[i + 1] : null;
                final showName = prev == null || prev['sender_id'] != m['sender_id'];
                return _Bubble(
                  msg: m,
                  mine: mine,
                  person: people[m['sender_id']],
                  showHeader: showName,
                  onOpen: _openAttachment,
                );
              },
            );
          },
        ),
      ),
      if (loadedRole) _composer(),
    ]);

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group['name']),
        actions: [
          IconButton(onPressed: _showMembers, icon: const Icon(Icons.groups_rounded)),
        ],
      ),
      body: body,
    );
  }

  Widget _composer() {
    final cs = Theme.of(context).colorScheme;
    if (myRole == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        color: cs.surfaceContainer,
        child: const Text('Join this group to take part.', textAlign: TextAlign.center),
      );
    }
    if (!canPost) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        color: cs.surfaceContainer,
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.campaign_rounded, size: 18, color: HC.peach),
          SizedBox(width: 8),
          Text('Only organisers can post announcements',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          IconButton(
              onPressed: sending ? null : _attach,
              icon: const Icon(Icons.attach_file_rounded)),
          Expanded(
            child: TextField(
              controller: input,
              minLines: 1,
              maxLines: 5,
              maxLength: 4000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  hintText: 'Message', counterText: '',
                  contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _send,
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(gradient: HC.grad, shape: BoxShape.circle),
              child: sending
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Icon(Icons.arrow_upward_rounded, color: Colors.white),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final Map<String, dynamic> msg;
  final bool mine, showHeader;
  final Map<String, dynamic>? person;
  final Future<void> Function(String, String) onOpen;
  const _Bubble(
      {required this.msg,
      required this.mine,
      required this.person,
      required this.showHeader,
      required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = person?['username'] ?? '...';
    final time = fmtTime(DateTime.parse(msg['created_at']));
    final hasFile = msg['attachment_path'] != null;
    final fg = mine ? Colors.white : cs.onSurface;

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .72),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      decoration: BoxDecoration(
        gradient: mine ? HC.grad : null,
        color: mine ? null : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(mine ? 20 : 5),
          bottomRight: Radius.circular(mine ? 5 : 20),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!mine && showHeader)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text('@$name',
                style: const TextStyle(
                    color: HC.sky, fontWeight: FontWeight.w800, fontSize: 12.5)),
          ),
        if (hasFile)
          InkWell(
            onTap: () => onOpen(msg['attachment_path'], msg['attachment_name'] ?? 'file'),
            child: Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.18), borderRadius: BorderRadius.circular(14)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.description_rounded, color: fg),
                const SizedBox(width: 8),
                Flexible(
                    child: Text(msg['attachment_name'] ?? 'file',
                        style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 6),
                Icon(Icons.download_rounded, size: 18, color: fg),
              ]),
            ),
          ),
        if ((msg['body'] ?? '').toString().isNotEmpty)
          Text(msg['body'], style: TextStyle(color: fg, fontSize: 15, height: 1.3)),
        const SizedBox(height: 2),
        Align(
            alignment: Alignment.bottomRight,
            child: Text(time,
                style: TextStyle(color: fg.withOpacity(.65), fontSize: 10.5))),
      ]),
    );

    return Padding(
      padding: EdgeInsets.only(top: showHeader ? 8 : 2),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine)
            SizedBox(
              width: 34,
              child: showHeader || true
                  ? Avatar(name: name, url: person?['avatar_url'], radius: 14)
                  : null,
            ),
          if (!mine) const SizedBox(width: 6),
          bubble,
        ],
      ),
    );
  }
}
