import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  const videoId = 'bKRCnm0T5ok';
  final yt = YoutubeExplode();
  final client = http.Client();

  // Test Web / Desktop (Default) client for offset 1.5MB
  print('--- Testing Default/Web client at offset 1.5MB ---');
  final m = await yt.videos.streamsClient.getManifest(videoId);
  for (final s in m.audioOnly) {
    if (s.size.totalBytes > 1500000) {
      final res = await client.get(s.url, headers: {'Range': 'bytes=1500000-1565535'});
      print('${s.container} (${s.audioCodec}) - size ${s.size.totalBytes} -> HTTP ${res.statusCode} (${res.bodyBytes.length} bytes)');
    }
  }

  client.close();
  yt.close();
}
