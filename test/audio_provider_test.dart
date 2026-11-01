import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:audiopulse_flutter/providers/audio_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'init') {
          return {'id': 'test_player_1'};
        }
        if (methodCall.method == 'load') {
          return {'duration': 218000000};
        }
        if (methodCall.method == 'disposeAllPlayers' ||
            methodCall.method == 'disposePlayer' ||
            methodCall.method == 'dispose') {
          return <String, dynamic>{};
        }
        return <String, dynamic>{};
      },
    );
  });

  group('AudioProvider State & Actions Tests', () {
    late AudioProvider provider;

    setUp(() {
      provider = AudioProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    test('Initial state loads tracks and mock playlists', () async {
      await Future.delayed(const Duration(milliseconds: 100));
      expect(provider.currentTrack, isNotNull);
      expect(provider.queue.isNotEmpty, true);
      expect(provider.allPlaylists.isNotEmpty, true);
      expect(provider.activeView, 'home');
    });

    test('Repeat mode cycles through off -> all -> one -> off', () {
      expect(provider.repeatMode, 'off');
      provider.toggleRepeat();
      expect(provider.repeatMode, 'all');
      provider.toggleRepeat();
      expect(provider.repeatMode, 'one');
      provider.toggleRepeat();
      expect(provider.repeatMode, 'off');
    });

    test('Toggle shuffle updates state', () {
      expect(provider.isShuffle, false);
      provider.toggleShuffle();
      expect(provider.isShuffle, true);
    });

    test('Playlist creation adds new playlist to store', () async {
      final initialCount = provider.allPlaylists.length;
      await provider.createNewPlaylist('Test Chillout', 'Cool vibe playlist');
      expect(provider.allPlaylists.length, initialCount + 1);
      expect(provider.allPlaylists[0].title, 'Test Chillout');
    });

    test('Adding track to playlist updates playlist tracks', () async {
      await Future.delayed(const Duration(milliseconds: 100));
      await provider.createNewPlaylist('Custom PL', 'Desc');
      final plId = provider.allPlaylists[0].id;
      final track = provider.allTracks[0];

      await provider.addTrackToUserPlaylist(plId, track);
      final pl = provider.allPlaylists.firstWhere((p) => p.id == plId);
      expect(pl.tracks.any((t) => t.id == track.id), true);
    });

    test('Settings autoDownload and autoPlayNext default to true and toggle accurately', () {
      expect(provider.autoDownload, true);
      expect(provider.autoPlayNext, true);

      provider.toggleAutoDownload();
      expect(provider.autoDownload, false);

      provider.toggleAutoPlayNext();
      expect(provider.autoPlayNext, false);

      provider.setAutoDownload(true);
      expect(provider.autoDownload, true);

      provider.setAutoPlayNext(true);
      expect(provider.autoPlayNext, true);
    });

    test('addToQueue appends track to the end of the queue', () async {
      await Future.delayed(const Duration(milliseconds: 100));
      final testTrack = provider.allTracks.first.copyWith(id: 'unique_queue_test_id', title: 'Queue Test');
      final initialQueueLength = provider.queue.length;

      provider.addToQueue(testTrack);
      expect(provider.queue.length, initialQueueLength + 1);
      expect(provider.queue.last.id, 'unique_queue_test_id');
    });

    test('playNextTrack inserts track directly after currently playing track', () async {
      await Future.delayed(const Duration(milliseconds: 100));
      final testTrack = provider.allTracks.first.copyWith(id: 'play_next_test_id', title: 'Play Next Test');
      final currentIdx = provider.queueIndex;

      provider.playNextTrack(testTrack);
      expect(provider.queue[currentIdx + 1].id, 'play_next_test_id');
    });
  });
}
