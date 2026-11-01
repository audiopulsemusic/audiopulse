import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  const videoId = 'bKRCnm0T5ok';
  final yt = YoutubeExplode();
  final manifest = await yt.videos.streamsClient.getManifest(videoId, ytClients: [YoutubeApiClient.android]);
  final audioStream = manifest.audioOnly.where((s) => s.container == StreamContainer.mp4).withHighestBitrate();
  final url = audioStream.url;

  final client = http.Client();

  // Test 1: Query param &range=0-1048575 vs &range=1048576-2097151
  print('--- Test Query Param range ---');
  final urlWithRange = url.replace(queryParameters: Map.from(url.queryParameters)..['range'] = '1048576-1310719');
  final res1 = await client.get(urlWithRange);
  print('Query param &range=1048576-1310719 -> HTTP ${res1.statusCode} (${res1.bodyBytes.length} bytes)');

  // Test 2: Headers with rn (range number) or User-Agent Android
  print('\n--- Test User-Agent Android YouTube App ---');
  final res2 = await client.get(
    url,
    headers: {
      'Range': 'bytes=1048576-1310719',
      'User-Agent': 'com.google.android.youtube/19.29.37 (Linux; U; Android 11) gzip',
    },
  );
  print('Android App User-Agent -> HTTP ${res2.statusCode} (${res2.bodyBytes.length} bytes)');

  // Test 3: WebM stream past 1MB
  print('\n--- Test WebM stream past 1MB ---');
  final webmStream = manifest.audioOnly.where((s) => s.container.name == 'webm').withHighestBitrate();
  final res3 = await client.get(
    webmStream.url,
    headers: {'Range': 'bytes=1048576-1310719'},
  );
  print('WebM stream past 1MB -> HTTP ${res3.statusCode} (${res3.bodyBytes.length} bytes)');

  client.close();
  yt.close();
}
