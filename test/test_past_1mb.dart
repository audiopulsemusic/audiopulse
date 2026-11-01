import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  const videoId = 'bKRCnm0T5ok';
  final yt = YoutubeExplode();

  // Test 1: Android Client
  print('=== 1. Testing Android Client ===');
  try {
    final mAndroid = await yt.videos.streamsClient.getManifest(videoId, ytClients: [YoutubeApiClient.android]);
    final sAndroid = mAndroid.audioOnly.where((s) => s.container == StreamContainer.mp4).withHighestBitrate();
    await testPast1MB(sAndroid.url, 'Android');
  } catch (e) {
    print('Android error: $e');
  }

  // Test 2: Default Client (Web/Desktop)
  print('\n=== 2. Testing Default Client ===');
  try {
    final mDefault = await yt.videos.streamsClient.getManifest(videoId);
    final sDefault = mDefault.audioOnly.where((s) => s.container == StreamContainer.mp4).withHighestBitrate();
    await testPast1MB(sDefault.url, 'Default');
  } catch (e) {
    print('Default error: $e');
  }

  // Test 3: iOS Client
  print('\n=== 3. Testing iOS Client ===');
  try {
    final mIos = await yt.videos.streamsClient.getManifest(videoId, ytClients: [YoutubeApiClient.ios]);
    final sIos = mIos.audioOnly.where((s) => s.container == StreamContainer.mp4).withHighestBitrate();
    await testPast1MB(sIos.url, 'iOS');
  } catch (e) {
    print('iOS error: $e');
  }

  yt.close();
}

Future<void> testPast1MB(Uri url, String name) async {
  final client = http.Client();
  final ranges = [
    'bytes=0-262143',
    'bytes=1048576-1310719', // ~1.0 MB - 1.3 MB
    'bytes=2097152-2359295', // ~2.0 MB - 2.3 MB
  ];
  for (final r in ranges) {
    final req = http.Request('GET', url)
      ..followRedirects = false
      ..headers['Range'] = r
      ..headers['Accept'] = '*/*';
    final res = await client.send(req);
    final bytes = await res.stream.fold<int>(0, (s, c) => s + c.length);
    print('[$name] $r -> HTTP ${res.statusCode} ($bytes bytes)');
  }
  client.close();
}
