import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../core/api.dart';
import '../core/local_db.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'notes_engine.dart';
import 'notes_viewer.dart';

class StudyScreen extends StatelessWidget {
  const StudyScreen({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Row(children: [
              Expanded(
                  child: Text('Study tools',
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -.5))),
              Pill('Works offline', color: HC.lime, icon: Icons.airplanemode_active_rounded),
            ]),
          ),
          const TabBar(
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: TextStyle(fontWeight: FontWeight.w800),
            tabs: [Tab(text: 'Make notes'), Tab(text: 'My notes'), Tab(text: 'Library')],
          ),
          const Expanded(
            child: TabBarView(children: [_Generate(), _MyNotes(), _Library()]),
          ),
        ]),
      );
}

// ---------------------------------------------------------------------------
class _Generate extends StatefulWidget {
  const _Generate();
  @override
  State<_Generate> createState() => _GenerateState();
}

class _GenerateState extends State<_Generate> with AutomaticKeepAliveClientMixin {
  final text = TextEditingController();
  final title = TextEditingController();
  double ratio = .35;
  bool busy = false;
  String? fileName;
  @override
  bool get wantKeepAlive => true;

  Future<void> _import() async {
    final r = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['txt', 'md'], withData: true);
    final f = r?.files.single;
    if (f == null || f.bytes == null) return;
    if (f.size > 2 * 1024 * 1024) {
      toast(context, 'Pick a text file under 2 MB', error: true);
      return;
    }
    setState(() {
      text.text = utf8.decode(f.bytes!, allowMalformed: true);
      fileName = f.name;
      if (title.text.isEmpty) title.text = f.name.replaceAll(RegExp(r'\.(txt|md)$'), '');
    });
  }

  Future<void> _generate() async {
    final t = text.text.trim();
    if (t.split(RegExp(r'\s+')).length < 40) {
      toast(context, 'Add a bit more text (at least ~40 words) to summarise', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      // Runs in a background isolate: UI stays smooth, no network involved.
      final json = await compute(generateNotesJson,
          {'text': t, 'title': title.text, 'ratio': ratio});
      final notes = GeneratedNotes.fromJson(json);
      if (notes.sections.isEmpty) throw Exception('Couldn\'t find enough content to summarise.');
      await LocalDb.saveNotes(notes.title, json);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => NotesViewer(notes: notes)));
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 30), children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            gradient: HC.gradLime.scale(.22), borderRadius: BorderRadius.circular(20)),
        child: const Row(children: [
          Icon(Icons.edit_note_rounded, color: HC.lime, size: 30),
          SizedBox(width: 12),
          Expanded(
              child: Text(
                  'Paste or import your notes. HUDDLE finds the key ideas, drops repetition and writes them up as handwritten revision pages - all on your phone.',
                  style: TextStyle(fontWeight: FontWeight.w600, height: 1.35))),
        ]),
      ),
      const SizedBox(height: 14),
      TextField(
          controller: title,
          maxLength: 60,
          decoration: const InputDecoration(labelText: 'Notes title (optional)', counterText: '')),
      const SizedBox(height: 10),
      TextField(
        controller: text,
        minLines: 8,
        maxLines: 14,
        decoration: InputDecoration(
          hintText: 'Paste your notes or textbook text here...\n\nTip: put headings on their own line.',
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _import,
            icon: const Icon(Icons.upload_file_rounded),
            label: Text(fileName ?? 'Import .txt / .md', overflow: TextOverflow.ellipsis),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
            onPressed: () => setState(() { text.clear(); fileName = null; }),
            icon: const Icon(Icons.clear_all_rounded)),
      ]),
      const SectionTitle('How short?'),
      SegmentedButton<double>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: .22, label: Text('Super short')),
          ButtonSegment(value: .35, label: Text('Balanced')),
          ButtonSegment(value: .55, label: Text('Detailed')),
        ],
        selected: {ratio},
        onSelectionChanged: (s) => setState(() => ratio = s.first),
      ),
      const SizedBox(height: 18),
      FilledButton.icon(
        onPressed: busy ? null : _generate,
        icon: busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.auto_awesome_rounded),
        label: Text(busy ? 'Writing your notes...' : 'Generate handwritten notes'),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(14)),
        child: const Row(children: [
          Icon(Icons.memory_rounded, size: 18),
          SizedBox(width: 10),
          Expanded(
              child: Text(
                  'Engine: built-in on-device summariser (no internet needed). PDF/photo import isn\'t available yet - paste the text or use .txt/.md.',
                  style: TextStyle(fontSize: 12.5))),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
class _MyNotes extends StatefulWidget {
  const _MyNotes();
  @override
  State<_MyNotes> createState() => _MyNotesState();
}

class _MyNotesState extends State<_MyNotes> {
  late Future<List<Map<String, dynamic>>> f = LocalDb.listNotes();
  void _reload() => setState(() => f = LocalDb.listNotes());

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: f,
        builder: (context, snap) {
          if (!snap.hasData) return const SkeletonList(count: 3);
          final rows = snap.data!;
          if (rows.isEmpty) {
            return EmptyState(
                icon: Icons.auto_stories_rounded,
                title: 'No notes yet',
                subtitle: 'Generated notes are saved on your phone and open without internet.',
                action: TextButton(onPressed: _reload, child: const Text('Refresh')));
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final r = rows[i];
                final j = Map<String, dynamic>.from(jsonDecode(r['json']));
                final n = GeneratedNotes.fromJson(j);
                return Dismissible(
                  key: ValueKey(r['id']),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    decoration: BoxDecoration(
                        color: HC.pink.withOpacity(.3), borderRadius: BorderRadius.circular(22)),
                    child: const Icon(Icons.delete_rounded),
                  ),
                  onDismissed: (_) async {
                    await LocalDb.deleteNotes(r['id']);
                    _reload();
                  },
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(14),
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                            color: const Color(0xFFFFFBF0), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.edit_note_rounded, color: Color(0xFF1D3A8A)),
                      ),
                      title: Text(n.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                          '${n.sections.length} sections · ${n.originalWords} → ${n.noteWords} words · ${fmtDate(DateTime.fromMillisecondsSinceEpoch(r['created_at']))}'),
                      onTap: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => NotesViewer(notes: n))),
                    ),
                  ),
                );
              },
            ),
          );
        },
      );
}

// ---------------------------------------------------------------------------
class _Library extends StatefulWidget {
  const _Library();
  @override
  State<_Library> createState() => _LibraryState();
}

class _LibraryState extends State<_Library> {
  late Future<List<Map<String, dynamic>>> f = LocalDb.listDownloads();
  void _reload() => setState(() => f = LocalDb.listDownloads());

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: f,
        builder: (context, snap) {
          if (!snap.hasData) return const SkeletonList(count: 3);
          final rows = snap.data!.where((r) => File(r['local_path']).existsSync()).toList();
          if (rows.isEmpty) {
            return EmptyState(
                icon: Icons.folder_open_rounded,
                title: 'No downloads yet',
                subtitle:
                    'Open a document shared in a class chat and it\'s saved here for offline reading.',
                action: TextButton(onPressed: _reload, child: const Text('Refresh')));
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => Card(
                child: ListTile(
                  leading: const Icon(Icons.description_rounded, color: HC.sky),
                  title: Text(rows[i]['name'], style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Available offline'),
                  trailing: const Icon(Icons.open_in_new_rounded),
                  onTap: () => OpenFilex.open(rows[i]['local_path']),
                ),
              ),
            ),
          );
        },
      );
}
