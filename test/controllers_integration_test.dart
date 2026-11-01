import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:audiopulse_flutter/models/album.dart';
import 'package:audiopulse_flutter/models/app_view.dart';
import 'package:audiopulse_flutter/models/artist.dart';
import 'package:audiopulse_flutter/models/search_engine_response.dart';
import 'package:audiopulse_flutter/models/track.dart';
import 'package:audiopulse_flutter/providers/audio_provider.dart';
import 'package:audiopulse_flutter/providers/download_controller.dart';
import 'package:audiopulse_flutter/providers/library_controller.dart';
import 'package:audiopulse_flutter/providers/navigation_controller.dart';
import 'package:audiopulse_flutter/providers/search_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'init') return {'id': 'controller_test'};
        if (methodCall.method == 'load') return {'duration': 218000000};
        if (methodCall.method == 'disposeAllPlayers' ||
            methodCall.method == 'disposePlayer' ||
            methodCall.method == 'dispose') {
          return <String, dynamic>{};
        }
        return <String, dynamic>{};
      },
    );
  });

    Track makeTrack(String id) => Track(
        id: id,
        title: 'Track $id',
        artist: 'Artist',
        coverUrl: '',
        audioUrl: 'yt://$id',
        duration: 120,
      );

  SearchEngineResponse nonEmptyResponse() => SearchEngineResponse(
        artists: const [],
        albums: const [],
        playlists: const [],
        tracks: [makeTrack('hit')],
        bestMatch: makeTrack('hit'),
      );

  group('NavigationController', () {
    test('selecting entities updates the active view', () {
      final nav = NavigationController();
      expect(nav.activeView, AppView.home);

      nav.selectArtist(Artist(id: 'a1', name: 'Daft', avatarUrl: '', bannerUrl: '', bio: ''));
      expect(nav.activeView, AppView.artist);
      expect(nav.selectedArtist, isNotNull);

      nav.selectAlbum(Album(
        id: 'al1',
        title: 'Discovery',
        artist: 'Daft Punk',
        coverUrl: '',
        releaseYear: 2001,
        tracksCount: 12,
        genre: 'Album',
        ambientColor: '#000000',
      ));
      expect(nav.activeView, AppView.album);

      nav.setView(AppView.search);
      expect(nav.activeView, AppView.search);
      nav.setFullPlayerOpen(true);
      expect(nav.isFullPlayerOpen, isTrue);
      nav.setQueueOpen(true);
      expect(nav.isQueueOpen, isTrue);
    });
  });

  group('DownloadController', () {
    test('deduplicates concurrent downloads of the same track id', () async {
      var streamCalls = 0;
      final controller = DownloadController(
        library: LibraryController(),
        fetchStream: (track, onProgress) async {
          streamCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return '/tmp/${track.id}.m4a';
        },
      );
      final track = makeTrack('dedup');
      final first = controller.download(track);
      final second = controller.download(track);
      final path1 = await first;
      final path2 = await second;
      expect(path1, path2);
      expect(streamCalls, 1);
    });

    test('transient null results are retried before failing', () async {
      var attempts = 0;
      final controller = DownloadController(
        library: LibraryController(),
        retryDelay: const Duration(milliseconds: 1),
        fetchStream: (track, onProgress) async {
          attempts++;
          // First four attempts behave like a transient YouTube block.
          if (attempts < 5) return null;
          return '/tmp/retried.m4a';
        },
      );
      final result = await controller.download(makeTrack('retry'));
      expect(result, isNotNull);
      expect(result!.localFilePath, '/tmp/retried.m4a');
      expect(attempts, 5);
    });

    test('gives up after exhausting the download retries', () async {
      var attempts = 0;
      final controller = DownloadController(
        library: LibraryController(),
        retryDelay: const Duration(milliseconds: 1),
        fetchStream: (track, onProgress) async {
          attempts++;
          return null;
        },
      );
      final result = await controller.download(makeTrack('exhaust'));
      expect(result, isNull);
      expect(attempts, 5);
    });

    test('progress is removed once the download settles', () async {
      final controller = DownloadController(
        library: LibraryController(),
        fetchStream: (track, onProgress) async {
          if (onProgress != null) onProgress(0.5);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return '/tmp/a.m4a';
        },
      );
      await controller.download(makeTrack('progress'));
      expect(controller.progress, isEmpty);
    });
  });

  group('SearchController stale protection', () {
    test('an older response cannot overwrite the newer search result', () async {
      final gated = <Completer<SearchEngineResponse>>[];
      final controller = SearchController(searchOperation: (query) {
        final completer = Completer<SearchEngineResponse>();
        gated.add(completer);
        return completer.future;
      });

      final first = controller.search('alpha');
      final second = controller.search('beta');
      expect(gated.length, 2);

      // The newer generation resolves with real results...
      gated[1].complete(nonEmptyResponse());
      // ...then the older generation resolves with empty results, late.
      gated[0].complete(SearchEngineResponse.empty());

      await Future.wait([first, second]);
      // The newer (non-empty) result must win; the late empty one is ignored.
      expect(controller.status, SearchStatus.success);
      expect(controller.results.isNotEmpty, isTrue);
    });

    test('clear() invalidates an in-flight request', () async {
      final gated = <Completer<SearchEngineResponse>>[];
      final controller = SearchController(searchOperation: (query) {
        final completer = Completer<SearchEngineResponse>();
        gated.add(completer);
        return completer.future;
      });

      final inFlight = controller.search('alpha');
      controller.clear();
      gated.single.complete(nonEmptyResponse());
      await inFlight;

      expect(controller.status, SearchStatus.idle);
      expect(controller.results.isEmpty, isTrue);
    });
  });

  group('AudioProvider navigation facade', () {
    test('setActiveView stays synchronized with the navigation controller', () {
      final provider = AudioProvider();
      provider.setActiveView('search');
      expect(provider.activeAppView, AppView.search);
      expect(provider.navigationController.activeView, AppView.search);
      provider.setIsFullPlayerOpen(true);
      expect(provider.navigationController.isFullPlayerOpen, isTrue);
      addTearDown(provider.dispose);
    });
  });
}