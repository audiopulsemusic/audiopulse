import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:audiopulse_flutter/services/fetch/yt_stream_resolver.dart';

class FakeAudioStreamInfo implements AudioOnlyStreamInfo {
  @override
  final Uri url;
  @override
  final FileSize size;
  @override
  final StreamContainer container;

  FakeAudioStreamInfo({
    required this.url,
    required this.size,
    required this.container,
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('YouTube range requests', () {
    test('caps every request to 256 KiB and uses exclusive end internally', () {
      final range = YouTubeAudioSource.calculateRange(0, 1024 * 1024, 1024 * 1024);
      expect(range.start, 0);
      expect(range.endExclusive, 256 * 1024);

      final later = YouTubeAudioSource.calculateRange(300000, 900000, 1000000);
      expect(later.start, 300000);
      expect(later.endExclusive, 300000 + 256 * 1024);
    });

    test('rejects ranges outside the known stream size', () {
      expect(
        () => YouTubeAudioSource.calculateRange(-1, 100, 1000),
        throwsRangeError,
      );
      expect(
        () => YouTubeAudioSource.calculateRange(0, 1001, 1000),
        throwsRangeError,
      );
    });

    test('YouTubeAudioSource streams chunks successfully and follows redirects', () async {
      final mockClient = MockClient((request) async {
        expect(request.followRedirects, isTrue);
        return http.Response.bytes(
          List.filled(100, 42),
          206,
          headers: {'content-range': 'bytes 0-99/100'},
        );
      });

      final streamInfo = FakeAudioStreamInfo(
        url: Uri.parse('https://rr1---sn.googlevideo.com/videoplayback'),
        size: const FileSize(100),
        container: StreamContainer.mp4,
      );

      final source = YouTubeAudioSource(
        streamInfo: streamInfo,
        httpClient: mockClient,
      );

      final response = await source.request(0, 100);
      expect(response.contentLength, 100);
      final bytes = await response.stream.fold<List<int>>([], (prev, elem) => prev..addAll(elem));
      expect(bytes.length, 100);
    });

    test('YouTubeAudioSource throws HttpException on non-200/206 status', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Forbidden', 403);
      });

      final streamInfo = FakeAudioStreamInfo(
        url: Uri.parse('https://rr1---sn.googlevideo.com/videoplayback'),
        size: const FileSize(100),
        container: StreamContainer.mp4,
      );

      final source = YouTubeAudioSource(
        streamInfo: streamInfo,
        httpClient: mockClient,
      );

      final response = await source.request(0, 100);
      expect(
        () => response.stream.drain<void>(),
        throwsA(isA<HttpException>()),
      );
    });
  });

  group('boundedNamePart sanitization', () {
    test('removes illegal filename characters', () {
      expect(YtStreamResolver.boundedNamePart('AC/DC'), 'AC_DC');
      expect(YtStreamResolver.boundedNamePart('a:b*c?'), 'a_b_c_');
      expect(YtStreamResolver.boundedNamePart('../../etc/passwd'), '____etc_passwd');
      expect(YtStreamResolver.boundedNamePart('..'), '_');
    });

    test('trim and fallback for empty names', () {
      expect(YtStreamResolver.boundedNamePart('   '), 'track');
      expect(YtStreamResolver.boundedNamePart(''), 'track');
    });

    test('caps very long names', () {
      final long = 'x' * 200;
      final bounded = YtStreamResolver.boundedNamePart(long);
      expect(bounded.length, lessThanOrEqualTo(40));
    });
  });

  group('detectExtensionFromHeader magic bytes', () {
    test('detects MP4/M4A (ftyp)', () {
      final header = [0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x4D, 0x34, 0x41, 0x20];
      expect(YtStreamResolver.detectExtensionFromHeader(header), 'm4a');
    });

    test('detects WebM/Matroska (EBML)', () {
      expect(YtStreamResolver.detectExtensionFromHeader([0x1A, 0x45, 0xDF, 0xA3, 0x00, 0x00]), 'webm');
    });

    test('detects Ogg (OggS)', () {
      expect(YtStreamResolver.detectExtensionFromHeader([0x4F, 0x67, 0x67, 0x53, 0x00, 0x02]), 'ogg');
    });

    test('detects MP3 (0xFFFB)', () {
      expect(YtStreamResolver.detectExtensionFromHeader([0xFF, 0xFB, 0x90, 0x64]), 'mp3');
    });

    test('returns null for unknown or short headers', () {
      expect(YtStreamResolver.detectExtensionFromHeader([1, 2, 3]), isNull);
      expect(YtStreamResolver.detectExtensionFromHeader([0x00, 0x00, 0x00, 0x00, 0x42]), isNull);
      expect(YtStreamResolver.detectExtensionFromHeader(const []), isNull);
    });
  });

  group('isAllowedAudioContentType', () {
    test('accepts audio types and common fallbacks', () {
      expect(YtStreamResolver.isAllowedAudioContentType('audio/mpeg'), isTrue);
      expect(YtStreamResolver.isAllowedAudioContentType('audio/mp4'), isTrue);
      expect(YtStreamResolver.isAllowedAudioContentType('audio/webm; codecs="opus"'), isTrue);
      expect(YtStreamResolver.isAllowedAudioContentType('application/ogg'), isTrue);
      expect(YtStreamResolver.isAllowedAudioContentType('application/octet-stream'), isTrue);
    });

    test('rejects non-audio content types', () {
      expect(YtStreamResolver.isAllowedAudioContentType('text/html'), isFalse);
      expect(YtStreamResolver.isAllowedAudioContentType('application/json'), isFalse);
      expect(YtStreamResolver.isAllowedAudioContentType('image/png'), isFalse);
    });
  });
}
