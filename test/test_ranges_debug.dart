import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  const videoId = 'bKRCnm0T5ok';
  final yt = YoutubeExplode();
  final manifest = await yt.videos.streamsClient.getManifest(videoId, ytClients: [YoutubeApiClient.android]);
  final audioStream = manifest.audioOnly.where((s) => s.container == StreamContainer.mp4).withHighestBitrate();
  final url = audioStream.url;
  print('Audio URL: $url');
  print('Total bytes: ${audioStream.size.totalBytes}');

  final ranges = [
    'bytes=0-262143',
    'bytes=262144-524287',
    'bytes=524288-786431',
    'bytes=786432-1048575',
    'bytes=1048576-1310719',
  ];

  final client = http.Client();
  for (final r in ranges) {
    final req = http.Request('GET', url)
      ..followRedirects = false
      ..headers['Range'] = r
      ..headers['Accept'] = '*/*';
    final sw = Stopwatch()..start();
    final res = await client.send(req);
    final bytes = await res.stream.fold<int>(0, (s, c) => s + c.length);
    sw.stop();
    print('$r -> HTTP ${res.statusCode} (${bytes} bytes in ${sw.elapsedMilliseconds}ms)');
  }
  client.close();
  yt.close();
}
