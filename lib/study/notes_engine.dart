import 'dart:math' as math;

/// On-device notes engine. Pure Dart: no network, no server, no API key.
///
/// It reads the text, finds the document's structure (headings), scores every
/// sentence by how central it is to the topic (TextRank-style term weighting),
/// drops repetition, keeps definitions + formulas verbatim, and condenses wording.
/// This is *extractive* summarisation - it picks and tightens the important
/// sentences; it does not paraphrase like an LLM would.

class NoteItem {
  final String text;
  final String kind; // point | definition | formula
  NoteItem(this.text, this.kind);
  Map<String, dynamic> toJson() => {'t': text, 'k': kind};
  factory NoteItem.fromJson(Map<String, dynamic> j) => NoteItem(j['t'], j['k']);
}

class NoteSection {
  final String heading;
  final List<NoteItem> items;
  final List<String> keywords;
  NoteSection(this.heading, this.items, this.keywords);
  Map<String, dynamic> toJson() =>
      {'h': heading, 'i': items.map((e) => e.toJson()).toList(), 'k': keywords};
  factory NoteSection.fromJson(Map<String, dynamic> j) => NoteSection(
        j['h'],
        (j['i'] as List).map((e) => NoteItem.fromJson(Map<String, dynamic>.from(e))).toList(),
        List<String>.from(j['k']),
      );
}

class GeneratedNotes {
  final String title;
  final List<String> keywords;
  final List<NoteSection> sections;
  final int originalWords, noteWords;
  GeneratedNotes(this.title, this.keywords, this.sections, this.originalWords, this.noteWords);

  Map<String, dynamic> toJson() => {
        'title': title,
        'keywords': keywords,
        'sections': sections.map((s) => s.toJson()).toList(),
        'ow': originalWords,
        'nw': noteWords,
      };
  factory GeneratedNotes.fromJson(Map<String, dynamic> j) => GeneratedNotes(
        j['title'],
        List<String>.from(j['keywords']),
        (j['sections'] as List).map((e) => NoteSection.fromJson(Map<String, dynamic>.from(e))).toList(),
        j['ow'],
        j['nw'],
      );
}

/// Top-level so it can run in a background isolate via `compute`.
Map<String, dynamic> generateNotesJson(Map<String, dynamic> args) =>
    NotesEngine.generate(args['text'] as String,
            title: args['title'] as String?, ratio: (args['ratio'] as num).toDouble())
        .toJson();

class NotesEngine {
  static const _stop = {
    'the','and','for','are','but','not','you','all','can','had','her','was','one','our','out','has','his','how','its','may','new','now','old','see','two','way','who','did','she','use','that','with','have','this','will','your','from','they','been','were','which','their','there','these','those','than','then','them','such','into','also','each','more','most','other','some','what','when','where','while','would','could','should','about','after','before','being','because','between','both','does','during','even','every','however','just','like','make','many','much','must','only','over','same','since','still','through','very','well','here','used','using','uses','called','known','refers','means','defined','thus','hence','therefore','example','shown'
  };

  static final _sentSplit = RegExp(r'(?<=[.!?])\s+(?=[A-Z0-9(])|\n+');
  static final _word = RegExp(r"[A-Za-z][A-Za-z'\-]+");
  static final _filler = RegExp(
      r'^(however|moreover|furthermore|in other words|for example|for instance|in addition|additionally|basically|essentially|as we know|as mentioned|it is important to note that|it should be noted that|note that|in fact|generally speaking|in simple terms)[,:]?\s+',
      caseSensitive: false);
  static final _formula = RegExp(r'(=|≈|≤|≥|∑|∫|√|\^|\bO\([^)]*\))');
  static final _defA = RegExp(
      r'\b(is defined as|can be defined as|is called|are called|is known as|are known as|refers to|stands for|is the process of|is a type of)\b',
      caseSensitive: false);
  static final _defB = RegExp(r'^[A-Z][\w\- ]{1,40}\s(is|are|means)\s(a|an|the)\s');

  static List<String> _tokens(String s) => _word
      .allMatches(s.toLowerCase())
      .map((m) => m.group(0)!)
      .where((w) => w.length > 2 && !_stop.contains(w))
      .toList();

  static bool _isHeading(String l) {
    final t = l.trim();
    if (t.isEmpty || t.length > 70) return false;
    if (t.startsWith('#')) return true;
    if (RegExp(r'^[-*•]\s').hasMatch(t)) return false;
    if (RegExp(r'[.!?;,]$').hasMatch(t)) return false;
    final words = t.split(RegExp(r'\s+'));
    if (words.length > 9) return false;
    final upper = t == t.toUpperCase() && RegExp(r'[A-Z]').hasMatch(t) && words.length <= 8;
    final numbered = RegExp(r'^(\d+(\.\d+)*[.)]?|chapter|unit|topic|module)\s+[A-Za-z]', caseSensitive: false).hasMatch(t) &&
        words.length <= 8;
    final colon = t.endsWith(':') && words.length <= 6;
    final caps = words.where((w) => w.isNotEmpty && w[0] == w[0].toUpperCase() && RegExp(r'[A-Za-z]').hasMatch(w[0])).length;
    final title = words.length <= 6 && caps >= words.length * .75 && !_formula.hasMatch(t);
    return upper || numbered || colon || title;
  }

  static String _cleanHeading(String h) =>
      h.replaceFirst(RegExp(r'^#+\s*'), '').replaceFirst(RegExp(r':$'), '').trim();

  static double _jaccard(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final i = a.intersection(b).length;
    return i / (a.length + b.length - i);
  }

  static String _condense(String s) {
    var t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
    t = t.replaceFirst(RegExp(r'^[-*•]\s*'), '');
    for (var i = 0; i < 2; i++) {
      final m = _filler.firstMatch(t);
      if (m != null) t = t.substring(m.end);
    }
    if (t.isNotEmpty) t = t[0].toUpperCase() + t.substring(1);
    // Trim very long ordinary points at a natural clause break.
    if (t.length > 170 && !_formula.hasMatch(t) && !_defA.hasMatch(t)) {
      final cut = RegExp(r'[,;]\s|\s(which|that|because|so that|whereas)\s')
          .allMatches(t)
          .map((m) => m.start)
          .where((p) => p > 70 && p < 160)
          .toList();
      if (cut.isNotEmpty) t = '${t.substring(0, cut.last).trimRight()}.';
    }
    return t;
  }

  static GeneratedNotes generate(String raw, {String? title, double ratio = .35}) {
    final text = raw.replaceAll('\r', '').trim();
    final allTokens = _tokens(text);
    final tf = <String, int>{};
    for (final w in allTokens) {
      tf[w] = (tf[w] ?? 0) + 1;
    }
    final maxTf = tf.values.isEmpty ? 1 : tf.values.reduce(math.max);

    // ---- 1. structure: split into sections by headings ----
    final blocks = <MapEntry<String?, List<String>>>[];
    String? head;
    var buf = <String>[];
    void flush() {
      if (buf.any((l) => l.trim().isNotEmpty)) blocks.add(MapEntry(head, buf));
      buf = [];
    }

    for (final line in text.split('\n')) {
      if (_isHeading(line)) {
        flush();
        head = _cleanHeading(line);
      } else {
        buf.add(line);
      }
    }
    flush();

    // No headings at all: chunk paragraphs and name chunks after their top keyword.
    if (blocks.length <= 1 && blocks.every((b) => b.key == null)) {
      final paras = text.split(RegExp(r'\n\s*\n')).where((p) => p.trim().isNotEmpty).toList();
      blocks.clear();
      var cur = <String>[];
      var words = 0;
      for (final p in paras) {
        cur.add(p);
        words += p.split(RegExp(r'\s+')).length;
        if (words > 220) {
          blocks.add(MapEntry(null, [cur.join('\n')]));
          cur = [];
          words = 0;
        }
      }
      if (cur.isNotEmpty) blocks.add(MapEntry(null, [cur.join('\n')]));
    }

    // ---- 2. per section: score, dedupe, condense ----
    final seen = <Set<String>>[];
    final sections = <NoteSection>[];
    var noteWords = 0;

    for (final b in blocks) {
      final body = b.value.join('\n');
      final sents = body
          .split(_sentSplit)
          .map((s) => s.trim())
          .where((s) => s.length >= 18 || _formula.hasMatch(s))
          .toList();
      if (sents.isEmpty) continue;

      final scored = <_S>[];
      for (var i = 0; i < sents.length; i++) {
        final s = sents[i];
        final toks = _tokens(s).toSet();
        if (toks.isEmpty && !_formula.hasMatch(s)) continue;
        var score = toks.fold<double>(0, (a, w) => a + (tf[w] ?? 0) / maxTf) / math.sqrt(toks.length + 4);
        final isDef = _defA.hasMatch(s) || _defB.hasMatch(s);
        final isFormula = _formula.hasMatch(s) && s.length < 140 && RegExp(r'[0-9a-zA-Z]\s*(=|≈|≤|≥)').hasMatch(s);
        if (isDef) score *= 1.5;
        if (isFormula) score *= 1.6;
        if (i == 0) score *= 1.25;
        if (RegExp(r'^[-*•]\s').hasMatch(s)) score *= 1.1;
        scored.add(_S(i, s, toks, score, isDef ? 'definition' : isFormula ? 'formula' : 'point'));
      }
      if (scored.isEmpty) continue;

      final want = (scored.length * ratio).ceil().clamp(2, 8);
      final ranked = [...scored]..sort((a, b) => b.score.compareTo(a.score));
      final picked = <_S>[];
      for (final c in ranked) {
        if (picked.length >= want) break;
        final dup = picked.any((p) => _jaccard(p.toks, c.toks) > .6) ||
            seen.any((p) => _jaccard(p, c.toks) > .75);   // repetition across sections too
        if (dup) continue;
        picked.add(c);
      }
      picked.sort((a, b) => a.idx.compareTo(b.idx));
      for (final p in picked) {
        seen.add(p.toks);
      }

      final items = picked.map((p) => NoteItem(_condense(p.text), p.kind)).toList();
      noteWords += items.fold<int>(0, (a, i) => a + i.text.split(' ').length);

      // section keywords
      final stf = <String, int>{};
      for (final w in _tokens(body)) {
        stf[w] = (stf[w] ?? 0) + 1;
      }
      final kws = (stf.entries.where((e) => (tf[e.key] ?? 0) >= 2).toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(4)
          .map((e) => e.key)
          .toList();

      final heading = b.key ?? (kws.isNotEmpty ? 'About ${_cap(kws.first)}' : 'Key ideas');
      sections.add(NoteSection(heading, items, kws));
    }

    // ---- 3. global keywords + title ----
    final kw = (tf.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .where((e) => e.value >= 2 && e.key.length > 3)
        .take(10)
        .map((e) => e.key)
        .toList();
    final t = (title != null && title.trim().isNotEmpty)
        ? title.trim()
        : kw.length >= 2 ? '${_cap(kw[0])} & ${_cap(kw[1])}' : kw.isNotEmpty ? _cap(kw[0]) : 'My Notes';

    return GeneratedNotes(t, kw, sections, text.split(RegExp(r'\s+')).length, noteWords);
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _S {
  final int idx;
  final String text, kind;
  final Set<String> toks;
  final double score;
  _S(this.idx, this.text, this.toks, this.score, this.kind);
}
