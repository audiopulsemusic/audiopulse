import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'network_exception.dart';

/// Shared network helpers: bounded retries with exponential backoff, status
/// classification, and safe JSON decoding that raise typed [NetworkException]s.
///
/// Kept dependency-free of the fetch services so it can be unit-tested without
/// a real network stack.
class NetworkGuard {
  const NetworkGuard._();

  /// True for errors worth retrying: timeouts and transient connectivity
  /// failures. Malformed payloads, auth/security rejections, and 4xx/5xx
  /// responses are not retried by default.
  static bool isTransient(Object error) {
    if (error is NetworkTimeoutException || error is NetworkUnavailableException) {
      return true;
    }
    if (error is TimeoutException) return true;
    if (error is SocketException) {
      return error.osError?.errorCode != null || error.message.contains('Connection refused');
    }
    if (error is http.ClientException) {
      return error.message.toLowerCase().contains('connection')
          || error.message.toLowerCase().contains('timed out')
          || error.message.toLowerCase().contains('socket');
    }
    return false;
  }

  /// Runs [operation], retrying up to [maxAttempts] times with exponential
  /// backoff when [isTransient] reports a retryable error. A non-transient
  /// failure is rethrown immediately.
  static Future<T> retryWithBackoff<T>({
    required Future<T> Function() operation,
    int maxAttempts = 3,
    Duration baseDelay = const Duration(milliseconds: 350),
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        return await operation();
      } catch (error) {
        lastError = error;
        if (!isTransient(error) || attempt == maxAttempts - 1) rethrow;
        await Future<void>.delayed(baseDelay * (attempt + 1));
      }
    }
    // Unreachable: the final attempt always rethrows.
    throw StateError('retryWithBackoff exited without result: $lastError');
  }

  /// Maps an HTTP status code to the matching typed exception.
  static Never statusError(http.BaseResponse response) {
    final status = response.statusCode;
    if (status == 404 || status == 410) {
      throw const ContentUnavailableException();
    }
    throw InvalidResponseException.status(status);
  }

  /// Forwards `response` or throws the matching [NetworkException] when the
  /// status is not in the success range.
  static T ensureSuccess<T extends http.BaseResponse>(T response,
      {List<int> accepted = const [200]}) {
    if (accepted.contains(response.statusCode)) return response;
    statusError(response);
  }

  /// Decodes a JSON map, throwing [InvalidResponseException] on malformed data
  /// or a structure that is not a JSON object.
  static Map<String, dynamic> decodeJsonObject(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const InvalidResponseException('Réponse JSON inattendue (objet attendu).');
      }
      return decoded;
    } on NetworkException {
      rethrow;
    } on FormatException catch (error) {
      throw InvalidResponseException('JSON invalide: ${error.message}');
    }
  }

  /// Decodes a JSON list, throwing [InvalidResponseException] on malformed data
  /// or a structure that is not a JSON array.
  static List<dynamic> decodeJsonList(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! List<dynamic>) {
        throw const InvalidResponseException('Réponse JSON inattendue (liste attendue).');
      }
      return decoded;
    } on NetworkException {
      rethrow;
    } on FormatException catch (error) {
      throw InvalidResponseException('JSON invalide: ${error.message}');
    }
  }

  static const Set<int> _redirectCodes = {301, 302, 303, 307, 308};

  /// Sends a GET without automatic redirects and validates every destination.
  static Future<http.StreamedResponse> getWithRedirects({
    required http.Client client,
    required Uri uri,
    required Future<void> Function(Uri uri) validate,
    Map<String, String> headers = const {},
    int maxRedirects = 3,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    var current = uri;
    for (var redirect = 0; redirect <= maxRedirects; redirect++) {
      await validate(current);
      final request = http.Request('GET', current)
        ..headers.addAll(headers)
        ..followRedirects = false;
      final response = await client.send(request).timeout(timeout);
      if (!_redirectCodes.contains(response.statusCode)) return response;
      await response.stream.drain<void>();
      if (redirect == maxRedirects) {
        throw const SecurityValidationException('Trop de redirections.');
      }
      final location = response.headers['location'];
      if (location == null || location.isEmpty) {
        throw const InvalidResponseException('Redirection sans destination.');
      }
      final next = current.resolve(location);
      if (next.scheme != current.scheme) {
        throw const SecurityValidationException('Changement de schéma interdit.');
      }
      current = next;
    }
    throw const SecurityValidationException('Trop de redirections.');
  }

  static bool isJsonContentType(String? value) {
    if (value == null || value.trim().isEmpty) return false;
    final type = value.toLowerCase().split(';').first.trim();
    return type == 'application/json' ||
        (type.startsWith('application/') && type.endsWith('+json'));
  }

  /// Reads a response under a strict byte ceiling.
  static Future<List<int>> readLimited(
    http.StreamedResponse response, {
    required int maxBytes,
  }) async {
    final declared = response.contentLength;
    if (declared != null && declared > maxBytes) {
      throw const SecurityValidationException('Réponse trop volumineuse.');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) {
        throw const SecurityValidationException('Réponse trop volumineuse.');
      }
    }
    return bytes;
  }
}
