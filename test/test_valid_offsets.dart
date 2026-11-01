import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  const videoId = 'bKRCnm0T5ok';
  final yt = YoutubeExplode();
  final client = http.Client();

  final manifest = await yt.videos.streamsClient.getManifest(videoId, ytClients: [YoutubeApiClient.android]);
  final audioStream = manifest.audioOnly.where((s) => s.container == StreamContainer.mp4).withHighestBitrate();
  
  final totalSize = audioStream.size.totalBytes;
  print('Stream: ${audioStream.container} ${audioStream.audioCodec} - Total size: $totalSize bytes (~${totalSize / (1024 * 1024)} MB)');

  // Let's test offsets throughout the entire file: 0, 500K, 1MB, 1.5MB, 2MB, 2.5MB
  final offsets = [0, 500000, 1000000, 1500000, 2000000, 2500000];
  for (final off in offsets) {
    if (off < totalSize) {
      final end = (off + 65535).clamp(0, totalSize - 1);
      final r = 'bytes=$off-$end';
      final res = await client.get(audioStream.url, headers: {'Range': r});
      print('Range $r -> HTTP ${res.statusCode} (${res.bodyBytes.length} bytes)');
    }
  }

  client.close();
  yt.close();
}
