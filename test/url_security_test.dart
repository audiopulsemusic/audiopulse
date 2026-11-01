import 'dart:io';

import 'package:audiopulse_flutter/services/api_service.dart';
import 'package:audiopulse_flutter/services/network/network_exception.dart';
import 'package:audiopulse_flutter/services/network/url_security_policy.dart';
import 'package:audiopulse_flutter/services/fetch/yt_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('BrowserHttpClient client profiles', () {
    test('maps YouTube c parameter to transport user agents', () {
      expect(BrowserHttpClient.clientProfile(Uri.parse('https://x.test/audio?c=ANDROID')), 'android');
      expect(BrowserHttpClient.clientProfile(Uri.parse('https://x.test/audio?c=ANDROID_VR')), 'android');
      expect(BrowserHttpClient.clientProfile(Uri.parse('https://x.test/audio?c=IOS')), 'ios');
      expect(BrowserHttpClient.clientProfile(Uri.parse('https://x.test/audio?c=TV')), 'tv');
      expect(BrowserHttpClient.clientProfile(Uri.parse('https://x.test/audio')), 'desktop');
      expect(BrowserHttpClient.userAgentFor(Uri.parse('https://x.test/audio?c=ANDROID')), contains('Android'));
      expect(BrowserHttpClient.userAgentFor(Uri.parse('https://x.test/audio?c=IOS')), contains('iPhone'));
    });
  });

  group('public HTTPS policy', () {
    test('rejects local, private, reserved and credentialed URLs', () {
      const blocked = [
        'http://example.com/audio.m4a',
        'https://localhost/audio.m4a',
        'https://example.local/audio.m4a',
        'https://127.0.0.1/audio.m4a',
        'https://10.0.0.1/audio.m4a',
        'https://169.254.169.254/latest/meta-data',
        'https://100.64.0.1/audio.m4a',
        'https://192.168.1.1/audio.m4a',
        'https://172.16.0.1/audio.m4a',
        'https://[::1]/audio.m4a',
        'https://[fc00::1]/audio.m4a',
        'https://[fe80::1]/audio.m4a',
        'https://user:pass@example.com/audio.m4a',
      ];
      for (final url in blocked) {
        expect(UrlSecurityPolicy.isSafePublicHttps(url), isFalse, reason: url);
      }
      expect(UrlSecurityPolicy.isSafePublicHttps('https://cdn.example.com/audio.m4a'), isTrue);
    });

    test('rejects a public hostname resolving to a private address', () async {
      await expectLater(
        UrlSecurityPolicy.validatePublicDestination(
          Uri.parse('https://cdn.example.com/audio.m4a'),
          resolver: (_) async => [InternetAddress('192.168.1.4')],
        ),
        throwsA(isA<SecurityValidationException>()),
      );
    });

    test('accepts a hostname resolving only to public addresses', () async {
      await UrlSecurityPolicy.validatePublicDestination(
        Uri.parse('https://cdn.example.com/audio.m4a'),
        resolver: (_) async => [InternetAddress('93.184.216.34')],
      );
    });
  });

  group('ApiService URL policy', () {
    test('health uses normalized path and no authentication header', () async {
      late http.Request request;
      final service = ApiService(client: MockClient((incoming) async {
        request = incoming;
        return http.Response('', 200);
      }));

      expect(await service.checkBackendHealth('https://api.musicpark.app/v1/'), isTrue);
      expect(request.url.toString(), 'https://api.musicpark.app/v1/health');
      expect(request.headers.containsKey('authorization'), isFalse);
      expect(service.config.mode, 'live');
    });

    test('rejects an arbitrary host before issuing a request', () async {
      var calls = 0;
      final service = ApiService(client: MockClient((_) async {
        calls++;
        return http.Response('', 200);
      }));

      expect(await service.checkBackendHealth('https://evil.example'), isFalse);
      expect(calls, 0);
      expect(service.lastError, isA<SecurityValidationException>());
      expect(service.config.mode, 'mock');
    });

    test('rejects redirects outside the original backend origin', () async {
      var calls = 0;
      final service = ApiService(client: MockClient((_) async {
        calls++;
        return http.Response('', 302, headers: {'location': 'https://evil.example/health'});
      }));

      expect(await service.checkBackendHealth('https://api.musicpark.app/v1'), isFalse);
      expect(calls, 1);
      expect(service.lastError, isA<SecurityValidationException>());
    });

    test('tracks rejects a non-JSON response', () async {
      final service = ApiService(client: MockClient((request) async {
        if (request.url.path.endsWith('/health')) return http.Response('', 200);
        return http.Response('<html/>', 200, headers: {'content-type': 'text/html'});
      }));
      expect(await service.checkBackendHealth('https://api.musicpark.app/v1'), isTrue);
      await expectLater(service.getTracks(), throwsA(isA<InvalidResponseException>()));
    });
  });
}
