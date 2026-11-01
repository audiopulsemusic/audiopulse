import 'package:flutter_test/flutter_test.dart';
import 'package:audiopulse_flutter/services/fetch/yt_utils.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  test('Test tag 18 streaming across multiple video IDs', () async {
    final yt = YoutubeExplode();
    final browserClient = BrowserHttpClient();
    try {
      final videoIds = ['NHZn-zXYAy8', 'bKRCnm0T5ok', 's5erlDt8Zj8'];
      for (final id in videoIds) {
        print('\n=== Testing video: $id ===');
        final manifest = await yt.videos.streamsClient.getManifest(id, ytClients: [YoutubeApiClient.android]);
        final muxed18 = manifest.muxed.where((s) => s.container == StreamContainer.mp4 && s.tag == 18);
        expect(muxed18.isNotEmpty, isTrue);
        final stream = muxed18.first;
        print('Tag 18 URL found: ${stream.url}');
        print('Size: ${stream.size.totalBytes} bytes');

        // Test seeking to 0%, 25%, 50%, 75%
        for (final fraction in [0.0, 0.25, 0.50, 0.75]) {
          final offset = (stream.size.totalBytes * fraction).toInt();
          final end = offset + 262143;
          final res = await browserClient.get(stream.url, headers: {'Range': 'bytes=$offset-$end'});
          print('  Offset ${(fraction * 100).toInt()}% ($offset bytes) -> HTTP ${res.statusCode} (${res.bodyBytes.length} bytes)');
          expect(res.statusCode, equals(206));
        }
        print('🎉 All seek offsets for $id succeeded with HTTP 206!');
      }
    } finally {
      yt.close();
      browserClient.close();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

