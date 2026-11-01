import 'package:audio_service/audio_service.dart';
import 'package:audiopulse_flutter/models/track.dart';
import 'package:audiopulse_flutter/providers/audio_provider.dart';
import 'package:audiopulse_flutter/services/audio_handler.dart';
import 'package:audiopulse_flutter/services/audio_player_service.dart';
import 'package:audiopulse_flutter/services/database_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall call) async {
        switch (call.method) {
          case 'init':
            return <String, dynamic>{'id': 'aa_test_player'};
          case 'load':
            return <String, dynamic>{'duration': 210000000};
          default:
            return <String, dynamic>{};
        }
      },
    );
  });

  group('AudioPulseHandler — Android Auto Playlists & Voice Search', () {
    late DatabaseService db;
    late AudioPlayer player;
    late AudioPulseHandler handler;

    final trackDaft1 = Track(
      id: 'trk_dp_1',
      title: 'One More Time',
      artist: 'Daft Punk',
      album: 'Discovery',
      albumId: 'alb_discovery',
      duration: 320,
      coverUrl: 'https://example.com/discovery.jpg',
      audioUrl: 'https://example.com/dp1.mp3',
      genre: 'Electronic',
      isFavorite: true,
    );

    final trackDaft2 = Track(
      id: 'trk_dp_2',
      title: 'Veridis Quo',
      artist: 'Daft Punk',
      album: 'Discovery',
      albumId: 'alb_discovery',
      duration: 345,
      coverUrl: 'https://example.com/discovery.jpg',
      audioUrl: 'https://example.com/dp2.mp3',
      genre: 'Electronic',
    );

    final trackAcdc = Track(
      id: 'trk_acdc_1',
      title: 'Thunderstruck',
      artist: 'AC/DC',
      album: 'The Razors Edge / Live',
      duration: 292,
      coverUrl: 'https://example.com/acdc.jpg',
      audioUrl: 'https://example.com/acdc.mp3',
      genre: 'Rock',
    );

    setUp(() async {
      db = DatabaseService.instance;
      await db.clearAllData();
      await db.insertOrUpdateTrack(trackDaft1);
      await db.insertOrUpdateTrack(trackDaft2);
      await db.insertOrUpdateTrack(trackAcdc);

      final sportPlaylist = await db.createPlaylist('Sport Intense', 'Cardio');
      await db.addTrackToPlaylist(sportPlaylist.id, trackAcdc);
      await db.addTrackToPlaylist(sportPlaylist.id, trackDaft1);

      player = AudioPlayer();
      handler = AudioPulseHandler(player, database: db);
    });

    tearDown(() async {
      await player.dispose();
    });

    test('advertises playFromSearch, playFromMediaId, and skipToQueueItem actions', () {
      final actions = handler.playbackState.value.systemActions;
      expect(
        actions,
        containsAll(<MediaAction>[
          MediaAction.playFromSearch,
          MediaAction.playFromMediaId,
          MediaAction.skipToQueueItem,
          MediaAction.stop,
        ]),
      );
    });

    test('exposes complete root tree and recent media resumption item', () async {
      final rootItems = await handler.getChildren(AudioService.browsableRootId);
      expect(
        rootItems.map((i) => i.id).toList(),
        equals(<String>[
          AudioPulseHandler.libraryNodeId,
          AudioPulseHandler.favoritesNodeId,
          AudioPulseHandler.playlistsNodeId,
          AudioPulseHandler.albumsNodeId,
        ]),
      );

      final recentItems = await handler.getChildren(AudioService.recentRootId);
      expect(recentItems, hasLength(1));
      expect(recentItems.first.playable, isTrue);
    });

    test('browses playlists and starts full playlist queue from selected track', () async {
      final playlists = await handler.getChildren(AudioPulseHandler.playlistsNodeId);
      expect(playlists, hasLength(1));
      final plItem = playlists.first;
      expect(plItem.title, 'Sport Intense');
      expect(plItem.playable, isFalse);
      // Cover fallback from first track in playlist
      expect(plItem.artUri.toString(), 'https://example.com/acdc.jpg');

      final plTracks = await handler.getChildren(plItem.id);
      expect(plTracks, hasLength(2));
      expect(plTracks[0].title, 'Thunderstruck');
      expect(plTracks[1].title, 'One More Time');

      Track? playedTrack;
      List<Track>? playedQueue;
      handler.onPlayTrackWithQueue = (track, queue) async {
        playedTrack = track;
        playedQueue = queue;
      };

      // Tap the second track inside the playlist in Android Auto
      await handler.playFromMediaId(plTracks[1].id);
      expect(playedTrack?.id, 'trk_dp_1');
      expect(playedQueue?.map((t) => t.id).toList(), <String>['trk_acdc_1', 'trk_dp_1']);
    });

    test('browses albums safely even when artist/album contains slashes (AC/DC)', () async {
      final albums = await handler.getChildren(AudioPulseHandler.albumsNodeId);
      expect(albums, hasLength(2));

      final acdcAlbum = albums.firstWhere((a) => a.artist == 'AC/DC');
      final albumTracks = await handler.getChildren(acdcAlbum.id);
      expect(albumTracks, hasLength(1));
      expect(albumTracks.first.title, 'Thunderstruck');

      Track? playedTrack;
      List<Track>? playedQueue;
      handler.onPlayTrackWithQueue = (track, queue) async {
        playedTrack = track;
        playedQueue = queue;
      };

      await handler.playFromMediaId(albumTracks.first.id);
      expect(playedTrack?.id, 'trk_acdc_1');
      expect(playedQueue?.map((t) => t.id).toList(), <String>['trk_acdc_1']);
    });

    test('syncQueue populates Android Auto queue and skipToQueueItem dispatches index', () async {
      handler.syncQueue(<Track>[trackDaft1, trackDaft2, trackAcdc], currentIndex: 0);
      expect(handler.queue.value, hasLength(3));
      expect(handler.playbackState.value.queueIndex, 0);

      int? skippedIndex;
      handler.onSkipToQueueItem = (idx) async {
        skippedIndex = idx;
      };

      await handler.skipToQueueItem(2);
      expect(skippedIndex, 2);
      expect(handler.playbackState.value.queueIndex, 2);
    });

    test('playFromSearch with empty query triggers resume or library shuffle', () async {
      var resumed = false;
      handler.onResumeOrShuffleLibrary = () async {
        resumed = true;
      };

      await handler.playFromSearch('');
      expect(resumed, isTrue);
    });

    test('playFromSearch plays matching playlist from French voice command or extras', () async {
      Track? playedTrack;
      List<Track>? playedQueue;
      handler.onPlayTrackWithQueue = (track, queue) async {
        playedTrack = track;
        playedQueue = queue;
      };

      await handler.playFromSearch('mets ma playlist sport intense');
      expect(playedTrack?.id, 'trk_acdc_1');
      expect(playedQueue?.map((t) => t.id).toList(), <String>['trk_acdc_1', 'trk_dp_1']);

      playedTrack = null;
      playedQueue = null;
      await handler.playFromSearch(
        'Sport',
        const <String, dynamic>{
          'android.intent.extra.focus': 'vnd.android.cursor.item/playlist',
          'android.intent.extra.playlist': 'Sport Intense',
        },
      );
      expect(playedTrack?.id, 'trk_acdc_1');
      expect(playedQueue, hasLength(2));
    });

    test('playFromSearch resolves fuzzy track, artist, and album queries', () async {
      Track? playedTrack;
      List<Track>? playedQueue;
      handler.onPlayTrackWithQueue = (track, queue) async {
        playedTrack = track;
        playedQueue = queue;
      };

      // Fuzzy track with typo ("veridis quoo")
      await handler.playFromSearch('joue veridis quoo');
      expect(playedTrack?.id, 'trk_dp_2');
      expect(playedQueue?.map((t) => t.id).toSet(), containsAll(<String>['trk_dp_1', 'trk_dp_2']));

      // Artist focus queues all Daft Punk tracks
      await handler.playFromSearch(
        'Daft Punk',
        const <String, dynamic>{
          'android.intent.extra.focus': 'vnd.android.cursor.item/artist',
          'android.intent.extra.artist': 'Daft Punk',
        },
      );
      expect(playedQueue, hasLength(2));
      expect(playedQueue!.every((t) => t.artist == 'Daft Punk'), isTrue);

      // Album command
      await handler.playFromSearch("lance l'album Discovery");
      expect(playedQueue, hasLength(2));
    });

    test('playFromSearch falls back to online search and clears loading state if empty', () async {
      final onlineTrack = Track(
        id: 'online_999',
        title: 'Midnight City',
        artist: 'M83',
        album: 'Hurry Up, We Are Dreaming',
        duration: 243,
        coverUrl: 'https://example.com/m83.jpg',
        audioUrl: 'https://example.com/m83.mp3',
        genre: 'Synthpop',
      );

      Track? playedTrack;
      handler.onPlayTrackWithQueue = (track, queue) async {
        playedTrack = track;
      };
      handler.onOnlineSearchFallback = (q) async {
        if (q.toLowerCase().contains('midnight')) {
          return <Track>[onlineTrack];
        }
        return const <Track>[];
      };

      await handler.playFromSearch('Midnight City M83');
      expect(playedTrack?.id, 'online_999');

      // Unknown query with empty online fallback must not leave state stuck in loading
      playedTrack = null;
      handler.clearTransitionState();
      await handler.playFromSearch('zzzzzz_non_existent_xyz');
      expect(playedTrack, isNull);
      expect(
        handler.playbackState.value.processingState,
        isNot(AudioProcessingState.loading),
      );
    });

    test('search() returns grouped Playlists, Albums, Titres, and online fallback playable via playFromMediaId', () async {
      final onlineTrack = Track(
        id: 'online_search_1',
        title: 'Aerodynamic',
        artist: 'Daft Punk',
        album: 'Discovery',
        duration: 212,
        coverUrl: 'https://example.com/discovery.jpg',
        audioUrl: 'https://example.com/aero.mp3',
        genre: 'Electronic',
      );
      handler.onOnlineSearchFallback = (_) async => <Track>[onlineTrack];

      final results = await handler.search('Discovery');
      final groups = results
          .map((i) => i.extras?[AudioPulseHandler.contentStyleGroupTitleHintKey])
          .toSet();
      expect(groups, containsAll(<String>['Albums', 'Titres', 'Catalogue en ligne']));

      // Tapping the transient online search result in Android Auto plays it immediately
      final onlineItem = results.firstWhere(
        (i) => i.extras?['trackId'] == 'online_search_1',
      );
      Track? playedTrack;
      handler.onPlayTrackWithQueue = (t, _) async => playedTrack = t;
      await handler.playFromMediaId(onlineItem.id);
      expect(playedTrack?.id, 'online_search_1');
    });

    test('AudioProvider.attachAudioHandler wires playlist playback and skipToQueueItem end-to-end', () async {
      final playerService = AudioPlayerService();
      final provider = AudioProvider(playerService);
      addTearDown(provider.dispose);

      await provider.refreshTracksFromDatabase();
      provider.attachAudioHandler(handler);

      // Voice command on handler drives AudioProvider queue + currentTrack
      await handler.playFromSearch('mets ma playlist sport intense');
      expect(provider.currentTrack?.id, 'trk_acdc_1');
      expect(provider.queue.map((t) => t.id).toList(), <String>['trk_acdc_1', 'trk_dp_1']);
      expect(handler.queue.value.map((i) => i.id).toList(), <String>['trk_acdc_1', 'trk_dp_1']);

      // Car head unit queue jump updates AudioProvider active track and index
      await handler.skipToQueueItem(1);
      expect(provider.queueIndex, 1);
      expect(provider.currentTrack?.id, 'trk_dp_1');
    });
  });
}
