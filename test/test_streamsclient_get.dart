import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  const videoId = 'bKRCnm0T5ok';
  final yt = YoutubeExplode();
  try {
    final manifest = await yt.videos.streamsClient.getManifest(videoId, ytClients: [YoutubeApiClient.android]);
    final audioStream = manifest.audioOnly.where((s) => s.container == StreamContainer.mp4).withHighestBitrate();
    final totalSize = audioStream.size.totalBytes;
    print('Testing streamsClient.get(audioStream) for $totalSize bytes...');

    final sw = Stopwatch()..start();
    final stream = yt.videos.streamsClient.get(audioStream);
    int totalBytes = 0;
    int chunkCount = 0;
    await for (final chunk in stream) {
      chunkCount++;
      totalBytes += chunk.length;
      if (chunkCount % 5 == 0 || totalBytes >= totalSize) {
        print('Chunk $chunkCount: total $totalBytes / $totalSize bytes in ${sw.elapsedMilliseconds}ms');
      }
    }
    sw.stop();
    print('SUCCESS! Read $totalBytes / $totalSize bytes in ${sw.elapsedMilliseconds}ms');
  } catch (e, st) {
    print('Error: $e');
    print('Stack: $st');
  } finally {
    yt.close();
  }
}
