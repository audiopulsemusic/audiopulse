import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiopulse_flutter/models/track.dart';
import 'package:audiopulse_flutter/services/fetch/yt_stream_resolver.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  HttpOverrides.global = null;

  group('Audio playback and auto-download tests for bKRCnm0T5ok and s5erlDt8Zj8', () {
    late YtStreamResolver resolver;

    setUp(() {
      resolver = YtStreamResolver();
    });

    for (final videoId in ['bKRCnm0T5ok', 's5erlDt8Zj8']) {
      test('resolves stream info and valid HTTPS audio source for $videoId', () async {
        final track = Track(
          id: videoId,
          title: 'Test Track $videoId',
          artist: 'Test Artist',
          audioUrl: 'yt://$videoId',
          duration: 180,
          coverUrl: '',
        );

        final streamInfo = await resolver.getAudioStreamInfo(videoId);
        expect(streamInfo, isNotNull);
        expect(streamInfo!.size.totalBytes, greaterThan(0));

        final audioSource = await resolver.resolveAudioSource(track);
        expect(audioSource, isNotNull);
        expect(audioSource, isA<AudioSource>());
        if (audioSource is YouTubeAudioSource) {
          expect(audioSource.streamInfo.url.host.contains('googlevideo.com') || audioSource.streamInfo.url.host.contains('piped'), isTrue);
        } else if (audioSource is UriAudioSource) {
          expect(audioSource.uri.scheme, 'https');
          expect(audioSource.uri.host.contains('googlevideo.com') || audioSource.uri.host.contains('piped'), isTrue);
        }
      });

      test('downloads full audio stream locally and returns existing file on playback for $videoId', () async {
        final track = Track(
          id: videoId,
          title: 'Test Track $videoId',
          artist: 'Test Artist',
          audioUrl: 'yt://$videoId',
          duration: 180,
          coverUrl: '',
        );

        final tempDir = Directory.systemTemp.createTempSync('audiopulse_test_download_');
        try {
          double lastProgress = 0.0;
          final downloadedPath = await resolver.downloadAudioStream(
            track,
            downloadsDir: tempDir,
            onProgress: (p) => lastProgress = p,
          );

          expect(downloadedPath, isNotNull);
          final downloadedFile = File(downloadedPath!);
          expect(downloadedFile.existsSync(), isTrue);
          expect(downloadedFile.lengthSync(), greaterThan(1000000));
          expect(lastProgress, closeTo(1.0, 0.01));

          // Calling downloadAudioStream a second time must immediately return the existing file path
          final secondDownloadPath = await resolver.downloadAudioStream(
            track,
            downloadsDir: tempDir,
          );
          expect(secondDownloadPath, downloadedPath);

          // When the track is marked as downloaded with its local file, resolveAudioSource must return a file AudioSource
          final downloadedTrack = track.copyWith(
            isDownloaded: true,
            localFilePath: downloadedPath,
          );
          final localSource = await resolver.resolveAudioSource(downloadedTrack);
          expect(localSource, isNotNull);
          expect(localSource, isA<ProgressiveAudioSource>());

          final playableUrl = await resolver.resolvePlayableAudioUrl(downloadedTrack);
          expect(playableUrl, downloadedPath);
        } finally {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        }
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
  });
}
