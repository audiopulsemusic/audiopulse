import 'package:flutter_test/flutter_test.dart';
import 'package:audiopulse_flutter/services/fuzzy_matcher.dart';

void main() {
  group('FuzzyMatcher Enhanced Tests', () {
    test('stripAccents folds accented characters to ASCII', () {
      expect(FuzzyMatcher.stripAccents('Beyoncé'), 'beyonce');
      expect(FuzzyMatcher.stripAccents('Émoi'), 'emoi');
      expect(FuzzyMatcher.stripAccents('Daft Punk'), 'daft punk');
    });

    test('normalize is accent-insensitive and collapses whitespace', () {
      expect(FuzzyMatcher.normalize('  Beyoncé   Bébé  '), 'beyonce bebe');
      expect(FuzzyMatcher.normalize('Cœur'), 'coeur');
    });

    test('accented query matches plain target with fuzzy scoring', () {
      final score = FuzzyMatcher.calculateScore(
        query: 'Beyoncé',
        title: 'Beyonce',
      );
      expect(score, greaterThan(120.0));
    });
    test('levenshtein calculates correct edit distance', () {
      expect(FuzzyMatcher.levenshtein('daft', 'daft'), 0);
      expect(FuzzyMatcher.levenshtein('ponk', 'punk'), 1);
      expect(FuzzyMatcher.levenshtein('lucki', 'lucky'), 1);
      expect(FuzzyMatcher.levenshtein('test', ''), 4);
    });

    test('normalize converts to lowercase and trims accurately', () {
      expect(FuzzyMatcher.normalize('  Music Box  '), 'music box');
      expect(FuzzyMatcher.normalize('Daft Punk'), 'daft punk');
    });

    test('tokenSimilarity matches artist prefix and mult-word combinations', () {
      // "YG" matching "YG - My Krazy Life"
      final ygScore = FuzzyMatcher.tokenSimilarity('YG', 'YG - My Krazy Life');
      expect(ygScore, greaterThan(0.7));

      // "daft ponk" matching "Daft Punk"
      final typoTokenScore = FuzzyMatcher.tokenSimilarity('daft ponk', 'Daft Punk');
      expect(typoTokenScore, greaterThan(0.7));
    });

    test('calculateScore yields high relevance scores with token similarity and signal boost', () {
      final exactScore = FuzzyMatcher.calculateScore(
        query: 'Daft Punk',
        title: 'Daft Punk',
      );
      final typoScore = FuzzyMatcher.calculateScore(
        query: 'daft ponk',
        title: 'Daft Punk',
      );
      final officialBoostScore = FuzzyMatcher.calculateScore(
        query: 'Daft Punk',
        title: 'Daft Punk',
        signalBoost: 35.0,
      );
      final unrelatedScore = FuzzyMatcher.calculateScore(
        query: 'YG BTP',
        title: 'Daft Punk',
      );

      expect(exactScore, greaterThan(150.0));
      expect(typoScore, greaterThan(80.0));
      expect(officialBoostScore, greaterThan(exactScore));
      expect(unrelatedScore, lessThan(30.0));
    });
  });
}
