import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'notes_engine.dart';

// Paper + pen colours
const _paper = Color(0xFFFFFBF0);
const _rule = Color(0xFFBFD7F2);
const _margin = Color(0xFFF2A0A0);
const _ink = Color(0xFF1D3A8A);
const _head = Color(0xFF7C3AED);
const _hi = Color(0xFFFFE45E);
const _lineH = 36.0;

/// Page-based, handwritten-looking notes on ruled paper.
class NotesViewer extends StatefulWidget {
  final GeneratedNotes notes;
  const NotesViewer({super.key, required this.notes});
  @override
  State<NotesViewer> createState() => _NotesViewerState();
}

class _NotesViewerState extends State<NotesViewer> {
  final pc = PageController();
  int page = 0;

  /// Splits sections into pages (max ~9 items each) so every page stays readable.
  List<Widget> _pages() {
    final n = widget.notes;
    final pages = <Widget>[_CoverPage(n)];
    for (final s in n.sections) {
      for (var i = 0; i < s.items.length; i += 9) {
        pages.add(_SectionPage(
          heading: s.heading + (i > 0 ? ' (cont.)' : ''),
          items: s.items.skip(i).take(9).toList(),
          keywords: {...n.keywords, ...s.keywords},
          showKw: i == 0 ? s.keywords : const [],
        ));
      }
    }
    return pages;
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages();
    return Scaffold(
      backgroundColor: const Color(0xFF2B2440),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2B2440),
        title: Text(widget.notes.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
                child: Text('${page + 1} / ${pages.length}',
                    style: const TextStyle(fontWeight: FontWeight.w800))),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: PageView(
            controller: pc,
            onPageChanged: (i) => setState(() => page = i),
            children: [
              for (final p in pages)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      decoration: const BoxDecoration(color: _paper, boxShadow: [
                        BoxShadow(color: Colors.black38, blurRadius: 18, offset: Offset(0, 8))
                      ]),
                      child: p,
                    ),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < pages.length && i < 14; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == page ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                      color: i == page ? const Color(0xFFC6F432) : Colors.white24,
                      borderRadius: BorderRadius.circular(8)),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _RuledPaper extends StatelessWidget {
  final Widget child;
  const _RuledPaper({required this.child});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: CustomPaint(
          painter: _RulePainter(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(58, 22, 18, 40),
            child: child,
          ),
        ),
      );
}

class _RulePainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = _rule
      ..strokeWidth = 1.2;
    for (double y = 22 + _lineH; y < s.height; y += _lineH) {
      c.drawLine(Offset(0, y), Offset(s.width, y), p);
    }
    c.drawLine(Offset(44, 0), Offset(44, s.height), Paint()..color = _margin..strokeWidth = 1.6);
  }

  @override
  bool shouldRepaint(_) => false;
}

TextStyle _hand({double size = 24, Color color = _ink, FontWeight w = FontWeight.w500}) =>
    GoogleFonts.caveat(fontSize: size, color: color, fontWeight: w, height: 1);

const _strut = StrutStyle(fontSize: 24, height: 1.5, forceStrutHeight: true);

/// Highlights keywords like a marker pen.
List<InlineSpan> _spans(String text, Set<String> kws, TextStyle base) {
  if (kws.isEmpty) return [TextSpan(text: text, style: base)];
  final re = RegExp('\\b(${kws.map(RegExp.escape).join('|')})\\b', caseSensitive: false);
  final out = <InlineSpan>[];
  var last = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > last) out.add(TextSpan(text: text.substring(last, m.start), style: base));
    out.add(TextSpan(
        text: m.group(0),
        style: base.copyWith(
            fontWeight: FontWeight.w800, backgroundColor: _hi.withOpacity(.75))));
    last = m.end;
  }
  if (last < text.length) out.add(TextSpan(text: text.substring(last), style: base));
  return out;
}

class _CoverPage extends StatelessWidget {
  final GeneratedNotes n;
  const _CoverPage(this.n);
  @override
  Widget build(BuildContext context) => _RuledPaper(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: _lineH),
          Text(n.title,
              strutStyle: const StrutStyle(fontSize: 44, height: 1.2, forceStrutHeight: true),
              style: _hand(size: 44, color: _head, w: FontWeight.w800)),
          Container(height: 4, width: 160, color: _head.withOpacity(.5), margin: const EdgeInsets.only(top: 4)),
          const SizedBox(height: _lineH),
          Text('Quick revision notes',
              strutStyle: _strut, style: _hand(size: 26, color: _ink, w: FontWeight.w700)),
          Text('${n.originalWords} words shrunk to ${n.noteWords}',
              strutStyle: _strut, style: _hand(size: 24)),
          const SizedBox(height: _lineH),
          Text('Key words', strutStyle: _strut, style: _hand(size: 26, color: _head, w: FontWeight.w800)),
          Wrap(spacing: 10, children: [
            for (final k in n.keywords)
              Text(k,
                  strutStyle: _strut,
                  style: _hand(size: 24, w: FontWeight.w800)
                      .copyWith(backgroundColor: _hi.withOpacity(.75))),
          ]),
          const SizedBox(height: _lineH),
          Text('Swipe → to start', strutStyle: _strut, style: _hand(size: 22, color: Colors.black45)),
        ]),
      );
}

class _SectionPage extends StatelessWidget {
  final String heading;
  final List<NoteItem> items;
  final Set<String> keywords;
  final List<String> showKw;
  const _SectionPage(
      {required this.heading, required this.items, required this.keywords, required this.showKw});

  @override
  Widget build(BuildContext context) => _RuledPaper(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(heading,
              strutStyle: const StrutStyle(fontSize: 32, height: 1.125, forceStrutHeight: true),
              style: _hand(size: 32, color: _head, w: FontWeight.w800).copyWith(
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.wavy,
                  decorationColor: _head.withOpacity(.6))),
          for (final it in items) _item(it),
          if (showKw.isNotEmpty) ...[
            const SizedBox(height: _lineH / 2),
            Text('★ remember: ${showKw.join(', ')}',
                strutStyle: _strut, style: _hand(size: 22, color: Colors.deepOrange.shade700, w: FontWeight.w700)),
          ],
        ]),
      );

  Widget _item(NoteItem it) {
    switch (it.kind) {
      case 'definition':
        return Text.rich(
          TextSpan(children: [
            TextSpan(text: 'Def ✎  ', style: _hand(color: Colors.pink.shade600, w: FontWeight.w800)),
            ..._spans(it.text, keywords, _hand()),
          ]),
          strutStyle: _strut,
        );
      case 'formula':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
              border: Border.all(color: Colors.green.shade700, width: 1.6),
              borderRadius: BorderRadius.circular(8),
              color: Colors.green.withOpacity(.08)),
          child: Text(it.text,
              strutStyle: _strut,
              style: _hand(color: Colors.green.shade900, w: FontWeight.w800)),
        );
      default:
        return Text.rich(
          TextSpan(children: [
            TextSpan(text: '➜ ', style: _hand(color: _head, w: FontWeight.w800)),
            ..._spans(it.text, keywords, _hand()),
          ]),
          strutStyle: _strut,
        );
    }
  }
}
