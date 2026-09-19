import '../ai/query_router.dart'
    show aliasGroupName, aliasGroupOf, isMoneyQuestion, isPersonalQuestion;
import '../ai/retrieval.dart' show parseQueryDate;
import 'trend_series.dart';

/// Max charts under one answer.
const kMaxAnswerCharts = 2;

/// Charts for a personal measure question (no model). Empty unless personal,
/// names a chartable measure in [scan], and is not money/date-only.
List<TrendSeries> trendsForQuestion(String question, TrendScan scan) {
  final q = question.toLowerCase().trim();
  if (q.isEmpty) return const [];
  // Personal numbers only, not definitions.
  if (!isPersonalQuestion(q)) return const [];
  // Money asks are not measure trends.
  if (isMoneyQuestion(q)) return const [];
  // A specific calendar day is a lookup, not a trend.
  final qd = parseQueryDate(q);
  if (qd.hasMonth && qd.day != null) return const [];

  final group = aliasGroupOf(q);
  if (group < 0) return const [];
  final base = aliasGroupName(group);
  // Match by name whether pinned or not.
  var hits = [
    for (final s in [...scan.series, ...scan.others])
      if (s.key == base || s.key.startsWith('$base:')) s,
  ];
  if (hits.isEmpty) return const [];

  // Narrow on named qualifiers when present.
  final asked = qualifiersIn(q);
  if (asked.isNotEmpty) {
    final narrowed = [
      for (final s in hits)
        if (asked.any((m) => _qualifiersOf(s.key).contains(m))) s,
    ];
    if (narrowed.isNotEmpty) hits = narrowed;
  }

  // Most points first; tie-break by latest date.
  hits.sort((a, b) {
    final byCount = b.points.length.compareTo(a.points.length);
    return byCount != 0 ? byCount : b.latest.date.compareTo(a.latest.date);
  });
  return hits.take(kMaxAnswerCharts).toList();
}

/// Qualifiers in a series key ("glucose:fasting" → {fasting}).
Set<String> _qualifiersOf(String key) {
  final at = key.indexOf(':');
  return at < 0 ? const {} : key.substring(at + 1).split(',').toSet();
}
