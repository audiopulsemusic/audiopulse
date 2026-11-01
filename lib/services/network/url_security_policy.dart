import 'dart:io';

import 'network_exception.dart';

typedef HostResolver = Future<List<InternetAddress>> Function(String host);

/// Central URL policy used by backend APIs and public media downloads.
class UrlSecurityPolicy {
  const UrlSecurityPolicy._();

  static const Set<String> apiHosts = {
    'api.musicpark.app',
    'staging.musicpark.app',
  };

  static bool isSafePublicHttps(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && isSafePublicHttpsUri(uri);
  }

  static bool isSafePublicHttpsUri(Uri uri) {
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.hasAuthority == false) {
      return false;
    }
    final host = uri.host.toLowerCase();
    if (uri.userInfo.isNotEmpty ||
        host == 'localhost' ||
        host.endsWith('.local')) {
      return false;
    }
    final parsed = InternetAddress.tryParse(uri.host);
    return parsed == null || !isReservedAddress(parsed);
  }

  static Uri? normalizeApiBase(String value, {bool allowLocalDevelopment = true}) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
    if (uri.query.isNotEmpty || uri.fragment.isNotEmpty) return null;

    final host = uri.host.toLowerCase();
    final isLocal = host == 'localhost' || host == '127.0.0.1' || host == '::1';
    if (isLocal) {
      if (!allowLocalDevelopment || (uri.scheme != 'http' && uri.scheme != 'https')) {
        return null;
      }
    } else if (uri.scheme != 'https' || !apiHosts.contains(host)) {
      return null;
    }

    final normalizedPath = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    return uri.replace(
      scheme: uri.scheme.toLowerCase(),
      host: host,
      pathSegments: normalizedPath,
      query: null,
      fragment: null,
    );
  }

  static Uri appendPath(Uri base, String segment,
      {Map<String, String>? queryParameters}) {
    return base.replace(
      pathSegments: [...base.pathSegments.where((s) => s.isNotEmpty), segment],
      queryParameters: queryParameters,
      fragment: null,
    );
  }

  static Future<void> validatePublicDestination(
    Uri uri, {
    HostResolver resolver = InternetAddress.lookup,
  }) async {
    if (!isSafePublicHttpsUri(uri)) {
      throw const SecurityValidationException();
    }
    if (InternetAddress.tryParse(uri.host) != null) return;
    List<InternetAddress> addresses;
    try {
      addresses = await resolver(uri.host);
    } on SocketException catch (error) {
      throw NetworkUnavailableException(error.message);
    }
    if (addresses.isEmpty || addresses.any(isReservedAddress)) {
      throw const SecurityValidationException(
          'La destination DNS pointe vers une adresse locale ou réservée.');
    }
  }

  static bool isReservedAddress(InternetAddress address) {
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
      final a = bytes[0], b = bytes[1];
      return a == 0 ||
          a == 10 ||
          a == 127 ||
          (a == 100 && b >= 64 && b <= 127) ||
          (a == 169 && b == 254) ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 0) ||
          (a == 192 && b == 168) ||
          (a == 198 && (b == 18 || b == 19)) ||
          a >= 224;
    }
    if (address.type == InternetAddressType.IPv6 && bytes.length == 16) {
      final allZeroExceptLast = bytes.take(15).every((b) => b == 0);
      return bytes.every((b) => b == 0) ||
          (allZeroExceptLast && bytes[15] == 1) ||
          (bytes[0] & 0xFE) == 0xFC ||
          (bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80) ||
          bytes[0] == 0xFF;
    }
    return true;
  }
}
