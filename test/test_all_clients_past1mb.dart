import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  const videoId = 'bKRCnm0T5ok';
  final yt = YoutubeExplode();
  final client = http.Client();

  final allClients = [
    ('DEFAULT', null),
    ('android', [YoutubeApiClient.android]),
    ('ios', [YoutubeApiClient.ios]),
    ('tv', [YoutubeApiClient.tv]),
    ('safari', [YoutubeApiClient.safari]),
  ];

  for (final (name, cList) in allClients) {
    print('\n==================== $name ====================');
    try {
      final manifest = cList == null 
          ? await yt.videos.streamsClient.getManifest(videoId)
          : await yt.videos.streamsClient.getManifest(videoId, ytClients: cList);
      
      final audioStreams = manifest.audioOnly;
      print('Audio streams: ${audioStreams.length}');
      if (audioStreams.isNotEmpty) {
        final a = audioStreams.first;
        print('Testing ${a.container} (${a.audioCodec}) total size: ${a.size.totalBytes}');

        // Test offset 0
        final r0 = await client.get(a.url, headers: {'Range': 'bytes=0-10000'});
        print('  Offset 0 -> HTTP ${r0.statusCode}');

        // Test offset 1.5MB
        final r1 = await client.get(a.url, headers: {'Range': 'bytes=1500000-1510000'});
        print('  Offset 1.5MB -> HTTP ${r1.statusCode}');

        if (r1.statusCode == 206) {
          print('  🎉 CLIENT $name SUCCEEDED PAST 1MB!');
        }
      }
    } catch (e) {
      print('Client $name error: $e');
    }
  }

  client.close();
  yt.close();
}
