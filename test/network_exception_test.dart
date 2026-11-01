import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:audiopulse_flutter/services/network/network_exception.dart';
import 'package:audiopulse_flutter/services/network/network_guard.dart';

void main() {
  group('Typed network exceptions', () {
    test('are sealed subtypes of NetworkException', () {
      const exceptions = [
        NetworkTimeoutException(),
        NetworkUnavailableException(),
        InvalidResponseException(),
        ContentUnavailableException(),
        StreamResolutionException(),
        SecurityValidationException(),
        DownloadException(),
      ];
      for (final e in exceptions) {
        expect(e, isA<NetworkException>());
        expect(e, isA<Exception>());
      }
    });

    test('distinct types are not interchangeable', () {
      expect(const NetworkTimeoutException(),
          isNot(isA<ContentUnavailableException>()));
      expect(const StreamResolutionException(),
          isNot(isA<InvalidResponseException>()));
    });
  });

  group('NetworkGuard.statusError', () {
    test('404 maps to ContentUnavailableException', () {
      final res = http.Response('', 404);
      expect(
        () => NetworkGuard.ensureSuccess(res),
        throwsA(isA<ContentUnavailableException>()),
      );
    });

    test('5xx maps to InvalidResponseException with server message', () {
      final res = http.Response('', 500);
      expect(
        () => NetworkGuard.ensureSuccess(res),
        throwsA(isA<InvalidResponseException>()),
      );
    });

    test('200 is accepted', () {
      final res = http.Response('ok', 200);
      expect(NetworkGuard.ensureSuccess(res).statusCode, 200);
    });
  });

  group('NetworkGuard.decode helpers', () {
    test('decodeJsonObject parses a valid map and rejects scalars', () {
      final ok = http.Response('{"a": 1}', 200);
      expect(NetworkGuard.decodeJsonObject(ok), {'a': 1});

      final scalar = http.Response('5', 200);
      expect(
        () => NetworkGuard.decodeJsonObject(scalar),
        throwsA(isA<InvalidResponseException>()),
      );
    });

    test('decodeJsonList parses a valid list and rejects malformed JSON', () {
      final ok = http.Response('[1,2]', 200);
      expect(NetworkGuard.decodeJsonList(ok), [1, 2]);

      final bad = http.Response('not json', 200);
      expect(
        () => NetworkGuard.decodeJsonList(bad),
        throwsA(isA<InvalidResponseException>()),
      );
    });
  });

  group('NetworkGuard.retryWithBackoff', () {
    test('returns the result when the operation eventually succeeds', () async {
      var calls = 0;
      final result = await NetworkGuard.retryWithBackoff(
        operation: () async {
          calls++;
          if (calls < 2) throw const NetworkUnavailableException();
          return 'done';
        },
        baseDelay: const Duration(milliseconds: 1),
      );
      expect(result, 'done');
      expect(calls, 2);
    });

    test('rethrows non-transient errors immediately without retrying', () async {
      var calls = 0;
      await expectLater(
        NetworkGuard.retryWithBackoff(
          operation: () async {
            calls++;
            throw const ContentUnavailableException();
          },
        ),
        throwsA(isA<ContentUnavailableException>()),
      );
      expect(calls, 1);
    });

    test('stops after reaching maxAttempts', () async {
      var calls = 0;
      await expectLater(
        NetworkGuard.retryWithBackoff(
          operation: () async {
            calls++;
            throw const NetworkUnavailableException();
          },
          maxAttempts: 3,
          baseDelay: const Duration(milliseconds: 1),
        ),
        throwsA(isA<NetworkUnavailableException>()),
      );
      expect(calls, 3);
    });

    test('classifies timeouts as transient', () {
      expect(NetworkGuard.isTransient(const NetworkTimeoutException()), isTrue);
      expect(NetworkGuard.isTransient(const NetworkUnavailableException()), isTrue);
      expect(NetworkGuard.isTransient(const InvalidResponseException()), isFalse);
      expect(NetworkGuard.isTransient(const SecurityValidationException()), isFalse);
    });
  });
}