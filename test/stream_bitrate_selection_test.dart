import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiopulse_flutter/services/fetch/yt_stream_resolver.dart';
import 'package:audiopulse_flutter/services/fetch/yt_utils.dart';
import 'package:audiopulse_flutter/models/track.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  HttpOverrides.global = null;

  group('Audio Stream & Bitrate Resolution', () {
    test('Resolves YouTube stream and provides realistic audio bitrate', () async {
      final resolver = YtStreamResolver();
      const videoId = 'bKRCnm0T5ok';

      final streamInfo = await resolver.getAudioStreamInfo(videoId);
      expect(streamInfo, isNotNull);

      final bitrateKbps = streamInfo!.bitrate.kiloBitsPerSecond.round();
      expect(bitrateKbps, greaterThanOrEqualTo(96));

      // Test with track and onBitrateResolved callback
      final track = Track(
        id: videoId,
        title: 'Test Bitrate Track',
        artist: 'Test Artist',
        audioUrl: 'yt://$videoId',
        duration: 160,
        coverUrl: '',
      );

      int? resolvedBitrate;
      final source = await resolver.resolveAudioSource(
        track,
        onBitrateResolved: (b) => resolvedBitrate = b,
      );

      expect(source, isNotNull);
      expect(resolvedBitrate, isNotNull);
      expect(resolvedBitrate!, greaterThanOrEqualTo(96));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('YouTubeAudioSource request emits valid audio chunks', () async {
      final resolver = YtStreamResolver();
      const videoId = 'bKRCnm0T5ok';
      final streamInfo = await resolver.getAudioStreamInfo(videoId);
      expect(streamInfo, isNotNull);
      final source = YouTubeAudioSource(
        streamInfo: streamInfo!,
        httpClient: BrowserHttpClient(),
      );
      final response = await source.request(0, null);
      int bytes = 0;
      await for (final chunk in response.stream) {
        bytes += chunk.length;
        if (bytes > 64 * 1024) break;
      }
      expect(bytes, greaterThan(0));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
