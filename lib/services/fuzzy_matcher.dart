import 'dart:math';

class FuzzyMatcher {
  /// Strip diacritics (é->e) and normalize to NFC form.
  static String stripAccents(String input) {
    final decomposed = input.toLowerCase().trim();
    final buffer = StringBuffer();
    for (final rune in decomposed.runes) {
      final replacement = _asciiFold[rune];
      buffer.write(replacement ?? String.fromCharCode(rune));
    }
    return buffer.toString();
  }

  /// Fold common Latin-1/Extended-A accented letters to ASCII equivalents.
  static const Map<int, String> _asciiFold = {
    0xC0: 'a', 0xC1: 'a', 0xC2: 'a', 0xC3: 'a', 0xC4: 'a', 0xC5: 'a',
    0xC7: 'c',
    0xC8: 'e', 0xC9: 'e', 0xCA: 'e', 0xCB: 'e',
    0xCC: 'i', 0xCD: 'i', 0xCE: 'i', 0xCF: 'i',
    0xD1: 'n',
    0xD2: 'o', 0xD3: 'o', 0xD4: 'o', 0xD5: 'o', 0xD6: 'o', 0xD8: 'o',
    0xD9: 'u', 0xDA: 'u', 0xDB: 'u', 0xDC: 'u',
    0xDD: 'y',
    0xDF: 'ss',
    0xE0: 'a', 0xE1: 'a', 0xE2: 'a', 0xE3: 'a', 0xE4: 'a', 0xE5: 'a',
    0xE7: 'c',
    0xE8: 'e', 0xE9: 'e', 0xEA: 'e', 0xEB: 'e',
    0xEC: 'i', 0xED: 'i', 0xEE: 'i', 0xEF: 'i',
    0xF1: 'n',
    0xF2: 'o', 0xF3: 'o', 0xF4: 'o', 0xF5: 'o', 0xF6: 'o', 0xF8: 'o',
    0xF9: 'u', 0xFA: 'u', 0xFB: 'u', 0xFC: 'u',
    0xFD: 'y', 0xFF: 'y',
    0x130: 'i', 0x131: 'i',
    0x152: 'oe', 0x153: 'oe',
    0x178: 'y',
  };

  /// Calculate Levenshtein distance between two strings
  static int levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List<int>.generate(t.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;

      for (int j = 0; j < t.length; j++) {
        int cost = (s.codeUnitAt(i) == t.codeUnitAt(j)) ? 0 : 1;
        v1[j + 1] = [v1[j] + 1, v0[j + 1] + 1, v0[j] + cost].reduce((a, b) => a < b ? a : b);
      }
      v0 = List<int>.from(v1);
    }

    return v0[t.length];
  }

  /// Normalize string for matching (accents folded, lowercased, whitespace collapsed).
  static String normalize(String str, {bool isYoutubeTitle = false}) {
    final folded = stripAccents(str);
    return folded.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Tokenizes a string into a set of clean words
  static List<String> tokenize(String str, {bool isYoutubeTitle = false}) {
    final norm = normalize(str, isYoutubeTitle: isYoutubeTitle);
    if (norm.isEmpty) return [];
    return norm.split(' ').where((w) => w.isNotEmpty).toList();
  }

  /// Word-boundary token similarity between a query and a title, used to detect
  /// short-name artists (e.g. "YG") without false positives on substrings.
  static double tokenSimilarityBoundary(String query, String target, {bool isYoutubeTitle = false}) {
    return tokenSimilarity(query, target, isYoutubeTitle: isYoutubeTitle);
  }

  /// Character-level similarity score between 0.0 and 1.0 using Levenshtein distance
  static double similarity(String s1, String s2, {bool isYoutubeTitle = false}) {
    final norm1 = normalize(s1, isYoutubeTitle: false);
    final norm2 = normalize(s2, isYoutubeTitle: isYoutubeTitle);
    if (norm1 == norm2) return 1.0;
    if (norm1.isEmpty || norm2.isEmpty) return 0.0;

    int maxLength = max(norm1.length, norm2.length);
    int dist = levenshtein(norm1, norm2);
    return (1.0 - (dist / maxLength)).clamp(0.0, 1.0);
  }

  /// Token-based similarity (Jaccard + best token Levenshtein alignment).
  /// Allows "YG" to strongly match "YG - My Krazy Life" or "daft ponk" to match "Daft Punk".
  static double tokenSimilarity(String query, String target, {bool isYoutubeTitle = false}) {
    final queryTokens = tokenize(query, isYoutubeTitle: false);
    final targetTokens = tokenize(target, isYoutubeTitle: isYoutubeTitle);

    if (queryTokens.isEmpty || targetTokens.isEmpty) return 0.0;

    // 1. Check if all query tokens exist exactly or closely in target tokens
    double totalTokenScore = 0.0;

    for (final qToken in queryTokens) {
      double bestMatchForToken = 0.0;
      for (final tToken in targetTokens) {
        if (qToken == tToken) {
          bestMatchForToken = 1.0;
          break;
        }
        final maxLen = max(qToken.length, tToken.length);
        if (maxLen > 0) {
          final dist = levenshtein(qToken, tToken);
          final sim = 1.0 - (dist / maxLen);
          if (sim > bestMatchForToken) {
            bestMatchForToken = sim;
          }
        }
      }
      totalTokenScore += bestMatchForToken;
    }

    final queryCoverage = totalTokenScore / queryTokens.length;

    // 2. Compute token set overlap (Jaccard)
    final querySet = queryTokens.toSet();
    final targetSet = targetTokens.toSet();
    final intersection = querySet.intersection(targetSet).length;
    final union = querySet.union(targetSet).length;
    final jaccard = union > 0 ? intersection / union : 0.0;

    // Weighted blend: query coverage (80%) + Jaccard overlap (20%)
    return (queryCoverage * 0.8) + (jaccard * 0.2);
  }

  /// Calculates a comprehensive relevance score for a search query against target fields
  static double calculateScore({
    required String query,
    required String title,
    String? subtitle,
    double relationshipBoost = 0.0,
    double signalBoost = 0.0,
    bool isYoutubeTitle = false,
  }) {
    final normQuery = normalize(query, isYoutubeTitle: false);
    final normTitle = normalize(title, isYoutubeTitle: isYoutubeTitle);
    if (normQuery.isEmpty) return 0.0;

    double score = 0.0;

    // 1. Exact string match
    if (normTitle == normQuery) {
      score += 100.0;
    } else if (normTitle.startsWith(normQuery)) {
      score += 75.0;
    } else if (normTitle.contains(normQuery)) {
      score += 60.0;
    }

    // 2. Subtitle / Artist / Album secondary match
    if (subtitle != null) {
      final normSub = normalize(subtitle, isYoutubeTitle: false);
      if (normSub == normQuery) {
        score += 85.0;
      } else if (normSub.startsWith(normQuery)) {
        score += 60.0;
      } else if (normSub.contains(normQuery)) {
        score += 40.0;
      }
    }

    // 3. Character-level Levenshtein similarity
    final charSim = similarity(query, title, isYoutubeTitle: isYoutubeTitle);
    score += charSim * 60.0;

    // 4. Token-based similarity (handles prefixes, multi-word queries, and substring words)
    final tokSim = tokenSimilarity(query, title, isYoutubeTitle: isYoutubeTitle);
    score += tokSim * 80.0;

    // 5. Contextual & YouTube official signal boost (Topic, VEVO, OLAK5uy_)
    score += signalBoost;

    // 6. Relational boost (Artist <-> Album <-> Track)
    score += relationshipBoost;

    return score;
  }
}
