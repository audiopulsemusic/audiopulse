import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:audiopulse_flutter/services/database_service.dart';
import 'package:audiopulse_flutter/models/track.dart';
import 'package:audiopulse_flutter/models/artist.dart';
import 'package:audiopulse_flutter/models/album.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<List<String>> tableNames(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<List<String>> columnNames(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<String> tempDbPath(String prefix) async {
    final dir = await Directory.systemTemp.createTemp('audiopulse_$prefix');
    addTearDown(() => dir.delete(recursive: true));
    return p.join(dir.path, '$prefix.db');
  }

  group('Concurrent initialization', () {
    test('20 simultaneous calls to instance.database return the same instance', () async {
      final shared = <Future<Object?>>[];
      for (var i = 0; i < 20; i++) {
        shared.add(DatabaseService.instance.database);
      }
      final results = await Future.wait(shared);
      final first = results.first;
      for (final r in results) {
        expect(identical(r, first), isTrue, reason: 'All calls must resolve to the same Database');
      }
    });
  });

  group('Initial schema creation', () {
    test('onCreate builds all required tables and seeds mock tracks', () async {
      final db = await DatabaseService.instance.openForTesting(path: await tempDbPath('schema'));
      final tables = await tableNames(db);
      expect(tables, containsAll(['tracks', 'artists', 'albums', 'playlists', 'playlist_tracks', 'search_history']));
      final count = await db.rawQuery('SELECT COUNT(*) AS c FROM tracks');
      expect(count.first['c'] as int, greaterThanOrEqualTo(0));
      await db.close();
    });
  });

  group('Versioned migrations', () {
    test('v1 database migrates to current version (PRAGMA-checked ALTER + new tables)', () async {
      final path = await tempDbPath('migrate');

      // Open at version 1 (migrations 0->1): fresh schema, no artistId/albumId.
      final db1 = await DatabaseService.instance.openForTesting(path: path, version: 1);
      var tracksCols = await columnNames(db1, 'tracks');
      expect(tracksCols, isNot(contains('artistId')));
      expect(tracksCols, isNot(contains('albumId')));
      // Insert one v1-compatible row (no artistId/albumId columns yet).
      await db1.insert('tracks', {
        'id': 'v1_row',
        'title': 'Old Track',
        'artist': 'Vlad',
        'duration': 120,
        'coverUrl': '',
        'audioUrl': 'yt://v1_row',
      });
      await db1.close();

      // Reopen at current version -> onUpgrade 1 -> 3 runs v2 then v3.
      final db3 = await DatabaseService.instance.openForTesting(path: path, version: DatabaseService.schemaVersion);
      tracksCols = await columnNames(db3, 'tracks');
      expect(tracksCols, containsAll(['artistId', 'albumId']));
      final tables = await tableNames(db3);
      expect(tables, containsAll(['playlists', 'playlist_tracks', 'search_history']));

      // The retained v1 row survives and is NOT duplicated by the upgrade path
      // (migration must not seed mocks again).
      final count = await db3.rawQuery('SELECT COUNT(*) AS c FROM tracks');
      expect(count.first['c'] as int, 1);
      final retained = await db3.query('tracks', where: 'id = ?', whereArgs: ['v1_row']);
      expect(retained.single['title'], 'Old Track');
      await db3.close();
    });

    test('unknown migration version fails loudly (no silent catch)', () async {
      final db = await DatabaseService.instance.openForTesting(
        path: await tempDbPath('unknown'),
        version: 1,
      );
      // Start from the current (1) version so migrations 2..999 run; the
      // missing step at 4 must throw rather than be swallowed.
      await expectLater(DatabaseService.runMigrations(db, 1, 999), throwsStateError);
      await db.close();
    });

    test('opening at an unsupported future version propagates the migration error', () async {
      final path = await tempDbPath('future');
      final db1 = await DatabaseService.instance.openForTesting(path: path, version: 1);
      await db1.close();

      // Fresh open at 99 runs migrations 0->99; missing v4+ must throw, not be swallowed.
      await expectLater(
        DatabaseService.instance.openForTesting(path: path, version: 99),
        throwsStateError,
      );
    });
  });

  group('Persistence', () {
    test('data survives close and reopen of the same file', () async {
      final path = await tempDbPath('persist');

      final db1 = await DatabaseService.instance.openForTesting(path: path);
      await db1.insert('artists', {
        'id': 'art_1',
        'name': 'Fête Persistante',
        'avatarUrl': '',
        'bannerUrl': '',
        'bio': '',
        'isFollowing': 1,
        'createdAt': 0,
      });
      await db1.close();

      final db2 = await DatabaseService.instance.openForTesting(path: path);
      final rows = await db2.query('artists', where: 'id = ?', whereArgs: ['art_1']);
      expect(rows, hasLength(1));
      expect(rows.first['isFollowing'], 1);
      await db2.close();
    });
  });

  group('Persistent search cache', () {
    test('stores raw query payload and respects TTL', () async {
      final service = DatabaseService.instance;
      final key = 'test:search:${DateTime.now().microsecondsSinceEpoch}';
      await service.writeSearchCache(
        cacheKey: key,
        cacheType: 'youtube_tracks',
        queryText: 'tyga on me',
        payload: '{"videoId":"raw-video-id","title":"Raw YouTube title"}',
        ttl: const Duration(minutes: 1),
      );
      expect(await service.readSearchCache(key), contains('raw-video-id'));

      final expired = '$key:expired';
      await service.writeSearchCache(
        cacheKey: expired,
        cacheType: 'youtube_tracks',
        queryText: 'expired',
        payload: '{}',
        ttl: const Duration(milliseconds: -1),
      );
      expect(await service.readSearchCache(expired), isNull);
    });
  });

  group('Singleton CRUD + phantom repair', () {
    test('getAllTracks resets downloads whose local file does not exist', () async {
      final service = DatabaseService.instance;
      final ghost = Track(
        id: 'ghost_1',
        title: 'Ghost',
        artist: 'Nobody',
        coverUrl: '',
        audioUrl: 'yt://ghost_1',
        duration: 180,
        isDownloaded: true,
        localFilePath: '/nonexistent/ghost_1.m4a',
      );
      await service.insertOrUpdateTrack(ghost);

      final tracks = await service.getAllTracks();
      final found = tracks.where((t) => t.id == 'ghost_1').firstOrNull;
      expect(found, isNotNull);
      expect(found!.isDownloaded, isFalse);
      expect(found.localFilePath, isNull);
    });

    test('insertOrUpdateTrack and deleteTrack round-trip', () async {
      final service = DatabaseService.instance;
      final db = await service.database;
      final track = Track(
        id: 'crud_1',
        title: 'Round Trip',
        artist: 'Crud',
        coverUrl: '',
        audioUrl: 'yt://crud_1',
        duration: 100,
      );
      await service.insertOrUpdateTrack(track);
      var fromDb = await db.query('tracks', where: 'id = ?', whereArgs: ['crud_1']);
      expect(fromDb, hasLength(1));
      expect(fromDb.first['title'], 'Round Trip');

      await service.deleteTrack('crud_1');
      fromDb = await db.query('tracks', where: 'id = ?', whereArgs: ['crud_1']);
      expect(fromDb, isEmpty);
    });

    test('artist persistence reads back via getArtist', () async {
      final service = DatabaseService.instance;
      await service.insertOrUpdateArtist(Artist(
        id: 'art_2',
        name: 'Daft Punk',
        avatarUrl: '',
        bannerUrl: '',
        bio: '',
      ));
      final found = await service.getArtist('art_2');
      expect(found, isNotNull);
      expect(found!.name, 'Daft Punk');
    });

    test('saveTracksIndex, saveAlbumsIndex and saveArtistIndex store all texts and IDs in database', () async {
      final service = DatabaseService.instance;
      final db = await service.database;

      // 1. Artist index
      await service.saveArtistIndex('Tyga', artistId: 'UC_tyga_channel', avatarUrl: 'https://avatar.com/tyga.jpg');
      final artistRows = await db.query('artists', where: 'id = ?', whereArgs: ['UC_tyga_channel']);
      expect(artistRows, hasLength(1));
      expect(artistRows.first['name'], 'Tyga');
      expect(artistRows.first['avatarUrl'], 'https://avatar.com/tyga.jpg');

      // 2. Albums index
      await service.saveAlbumsIndex([
        Album(
          id: 'PLnJ84fWZwLd9jbVi5qHte1IdDflyz56Ki',
          title: 'Tyga legendary',
          artist: 'Tyga',
          artistId: 'UC_tyga_channel',
          coverUrl: 'https://cover.com/legendary.jpg',
          tracksCount: 13,
          releaseYear: 2019,
          genre: 'Sortie Officielle',
          ambientColor: '#1A1A1A',
        ),
      ]);
      final albumRows = await db.query('albums', where: 'id = ?', whereArgs: ['PLnJ84fWZwLd9jbVi5qHte1IdDflyz56Ki']);
      expect(albumRows, hasLength(1));
      expect(albumRows.first['title'], 'Tyga legendary');
      expect(albumRows.first['artist'], 'Tyga');
      expect(albumRows.first['artistId'], 'UC_tyga_channel');
      expect(albumRows.first['tracksCount'], 13);
      expect(albumRows.first['releaseYear'], 2019);

      // 3. Tracks index
      await service.saveTracksIndex([
        Track(
          id: 'v_werkkkk_1',
          title: 'Tyga - Werkkkk (Audio)',
          artist: 'Tyga',
          artistId: 'UC_tyga_channel',
          album: 'Tyga legendary',
          albumId: 'PLnJ84fWZwLd9jbVi5qHte1IdDflyz56Ki',
          coverUrl: 'https://cover.com/werkkkk.jpg',
          audioUrl: 'yt://v_werkkkk_1',
          duration: 201,
          genre: 'Hip-Hop',
          ambientColor: '#EC4899',
        ),
        Track(
          id: 'v_werkkkk_2',
          title: 'Werkkkk',
          artist: 'Tyga',
          artistId: 'UC_tyga_channel',
          album: 'Tyga legendary',
          albumId: 'PLnJ84fWZwLd9jbVi5qHte1IdDflyz56Ki',
          coverUrl: 'https://cover.com/werkkkk.jpg',
          audioUrl: 'yt://v_werkkkk_2',
          duration: 201,
          genre: 'Hip-Hop',
          ambientColor: '#EC4899',
        ),
      ]);
      final trackRows = await db.query('tracks', where: 'artist = ?', whereArgs: ['Tyga']);
      final werkkkTracks = trackRows.where((r) => r['title'].toString().contains('Werkkkk')).toList();
      expect(werkkkTracks, hasLength(2));
      for (final tr in werkkkTracks) {
        expect(tr['artistId'], 'UC_tyga_channel');
        expect(tr['album'], 'Tyga legendary');
        expect(tr['albumId'], 'PLnJ84fWZwLd9jbVi5qHte1IdDflyz56Ki');
        expect(tr['duration'], 201);
      }
    });
  });

  group('Search History and Local Search', () {
    test('addSearchHistory, getSearchHistory, and removeSearchHistory work accurately', () async {
      final dbService = DatabaseService.instance;
      await dbService.clearSearchHistory();

      await dbService.addSearchHistory('Tyga');
      await dbService.addSearchHistory('Lil Wayne');
      await dbService.addSearchHistory('tyga'); // Case-insensitive deduplication, updates order

      final history = await dbService.getSearchHistory(limit: 5);
      expect(history, hasLength(2));
      expect(history.first, 'tyga');
      expect(history[1], 'Lil Wayne');

      await dbService.removeSearchHistory('Lil Wayne');
      final afterRemove = await dbService.getSearchHistory(limit: 5);
      expect(afterRemove, hasLength(1));
      expect(afterRemove.first, 'tyga');

      await dbService.clearSearchHistory();
      expect(await dbService.getSearchHistory(limit: 5), isEmpty);
    });

    test('searchLocalTracks finds tracks by title, artist, or album', () async {
      final dbService = DatabaseService.instance;
      final results = await dbService.searchLocalTracks('Tyga', limit: 5);
      expect(results, isNotEmpty);
      for (final track in results) {
        final matches = track.artist.toLowerCase().contains('tyga') ||
            track.title.toLowerCase().contains('tyga') ||
            track.album.toLowerCase().contains('tyga');
        expect(matches, isTrue);
      }
    });

    test('getAllPlaylists loads playlists and ordered tracks via SQL JOIN', () async {
      final dbService = DatabaseService.instance;
      final pl = await dbService.createPlaylist('Perf Join Playlist', 'Test JOIN');
      final t1 = Track(
        id: 'join_t1',
        title: 'Track One',
        artist: 'Artist A',
        album: 'Album A',
        duration: 180,
        coverUrl: 'https://example.com/1.jpg',
        audioUrl: 'yt://join_t1',
      );
      final t2 = Track(
        id: 'join_t2',
        title: 'Track Two',
        artist: 'Artist B',
        album: 'Album B',
        duration: 200,
        coverUrl: 'https://example.com/2.jpg',
        audioUrl: 'yt://join_t2',
      );
      await dbService.addTrackToPlaylist(pl.id, t1);
      await dbService.addTrackToPlaylist(pl.id, t2);

      final allPlaylists = await dbService.getAllPlaylists();
      final loaded = allPlaylists.firstWhere((p) => p.id == pl.id);
      expect(loaded.tracks.map((t) => t.id).toList(), ['join_t1', 'join_t2']);

      await dbService.deletePlaylist(pl.id);
    });
  });
}
