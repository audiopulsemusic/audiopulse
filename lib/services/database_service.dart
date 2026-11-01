import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/track.dart';
import '../models/artist.dart';
import '../models/album.dart';
import '../models/playlist.dart';
import '../models/collection_type.dart';
import '../data/mock_data.dart';
import 'fuzzy_matcher.dart';

/// Persistent single source of truth backed by SQLite.
///
/// The database is opened lazily and its initialization is serialized through a
/// shared `Future<Database>`: concurrent callers of `database` all await the
/// exact same open operation and receive the same [Database] instance.
///
/// Schema changes are expressed as explicit, independently testable versioned
/// migrations ([_migrations]). Migration steps must never swallow errors: a
/// failing migration surfaces to the caller instead of being hidden behind a
/// silent `catch (_) {}`.
class DatabaseService {
  final ValueNotifier<int> searchHistoryGeneration = ValueNotifier(0);
  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();

  /// Current schema version. Bump this and add a migration to [_migrations].
  static const int schemaVersion = 9;

  static const Map<int, Future<void> Function(Database)> _migrations = {
    1: _migrateToV1,
    2: _migrateToV2,
    3: _migrateToV3,
    4: _migrateToV4,
    5: _migrateToV5,
    6: _migrateToV6,
    7: _migrateToV7,
    8: _migrateToV8,
    9: _migrateToV9,
  };

  Future<Database>? _dbFuture;

  /// Lazily opens (once) and returns the shared [Database].
  ///
  /// All concurrent access observes the same in-flight [Future], meeting the
  /// "20 concurrent calls return the same base" acceptance criterion. If
  /// opening fails, the cached future is cleared so a later call can retry.
  Future<Database> get database => _dbFuture ??= _openSharedDatabase();

  Future<Database> _openSharedDatabase() async {
    try {
      final dbPath = await _resolveDatabasePath();
      final db = await _openDatabaseAt(dbPath, version: schemaVersion);
      // A pre-existing database (which never runs onCreate) lacks the mock
      // playlists. Seed them idempotently for the real app so the initial
      // library converges on the fresh-install layout.
      await _seedMockPlaylistsIfEmpty(db);
      await _ensurePerformanceIndexes(db);
      await _cleanTransientUnlistenedTracks(db);
      await _pruneSearchCacheSafe(db);
      return db;
    } catch (_) {
      _dbFuture = null;
      rethrow;
    }
  }

  /// Resolves the platform-specific default database path. Falls back to an
  /// in-memory database only when no file-backed location is available (test
  /// environment, or when path_provider fails on a supported platform).
  Future<String> _resolveDatabasePath() async {
    _setupPlatformFactory();
    try {
      if (!kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
        final supportDir = await getApplicationSupportDirectory();
        if (!await supportDir.exists()) {
          await supportDir.create(recursive: true);
        }
        return p.join(supportDir.path, 'audiopulse.db');
      }
      if (!kIsWeb) {
        final defaultPath = await getDatabasesPath();
        return p.join(defaultPath, 'audiopulse.db');
      }
    } catch (_) {
      return inMemoryDatabasePath;
    }
    return inMemoryDatabasePath;
  }

  /// Opens a database at [path] (or in-memory) at the given [version].
  ///
  /// Fresh databases run migrations `0 -> version` in [onCreate]; existing
  /// databases at an older version run only the pending increments in
  /// [onUpgrade]. Mock seeding happens exclusively in [onCreate], once, and is
  /// guarded by an empty-count check.
  @visibleForTesting
  Future<Database> openForTesting({
    DatabaseFactory? factory,
    String? path,
    int version = schemaVersion,
  }) async {
    _setupPlatformFactory(factory);
    return _openDatabaseAt(
      path ?? inMemoryDatabasePath,
      version: version,
      factory: factory,
    );
  }

  Future<Database> _openDatabaseAt(
    String dbPath, {
    int version = schemaVersion,
    DatabaseFactory? factory,
  }) async {
    final effectiveFactory = factory ?? _resolveFactory();
    return effectiveFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: (db, v) async {
          await runMigrations(db, 0, v);
          // Seed mock tracks only on a fresh install at the final schema
          // version. Intermediate-version opens (used in migration tests) do not
          // seed, and the upgrade path never seeds.
          if (v >= schemaVersion) {
            await _seedMockTracksIfEmpty(db);
          }
        },
        onUpgrade: (db, oldVersion, newVersion) =>
            runMigrations(db, oldVersion, newVersion),
      ),
    );
  }

  /// Fails loudly on unknown versions instead of silently proceeding.
  @visibleForTesting
  static Future<void> runMigrations(Database db, int from, int to) async {
    for (var v = from + 1; v <= to; v++) {
      final migration = _migrations[v];
      if (migration == null) {
        throw StateError('No migration defined for schema version $v (from $from to $to).');
      }
      await migration(db);
    }
  }

  static Future<void> _migrateToV1(Database db) async {
    await db.execute('''
      CREATE TABLE tracks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        album TEXT,
        duration INTEGER NOT NULL,
        coverUrl TEXT NOT NULL,
        audioUrl TEXT NOT NULL,
        localFilePath TEXT,
        isDownloaded INTEGER DEFAULT 0,
        isFavorite INTEGER DEFAULT 0,
        genre TEXT,
        ambientColor TEXT,
        lyrics TEXT,
        createdAt INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE artists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        avatarUrl TEXT,
        bannerUrl TEXT,
        bio TEXT,
        isFollowing INTEGER DEFAULT 0,
        createdAt INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE albums (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        artistId TEXT,
        coverUrl TEXT,
        releaseYear INTEGER,
        tracksCount INTEGER,
        genre TEXT,
        ambientColor TEXT,
        createdAt INTEGER
      )
    ''');
  }

  static Future<void> _migrateToV2(Database db) async {
    await _ensureColumn(db, 'tracks', 'artistId', 'TEXT');
    await _ensureColumn(db, 'tracks', 'albumId', 'TEXT');
  }

  static Future<void> _migrateToV3(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS playlists (
        id TEXT PRIMARY KEY,
        title TEXT,
        description TEXT,
        coverUrl TEXT,
        createdBy TEXT,
        isPublic INTEGER DEFAULT 1,
        ambientColor TEXT,
        createdAt INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS playlist_tracks (
        playlist_id TEXT NOT NULL,
        track_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        PRIMARY KEY (playlist_id, track_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS search_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        query TEXT NOT NULL,
        createdAt INTEGER
      )
    ''');
  }

  static Future<void> _migrateToV4(Database db) async {
    await _ensureColumn(db, 'tracks', 'releaseYear', 'INTEGER');
    await _ensureColumn(db, 'tracks', 'isExplicit', 'INTEGER DEFAULT 0');
    await _ensureColumn(db, 'albums', 'collectionType', 'TEXT');
  }

  static Future<void> _migrateToV5(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS search_cache (
        cacheKey TEXT PRIMARY KEY,
        cacheType TEXT NOT NULL,
        queryText TEXT NOT NULL,
        payload TEXT NOT NULL,
        expiresAt INTEGER NOT NULL,
        createdAt INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_search_cache_expiry ON search_cache(expiresAt)');
  }

  static Future<void> _migrateToV6(Database db) async {
    await _ensureColumn(db, 'tracks', 'source', 'TEXT DEFAULT "music"');
    await db.delete('search_cache');
  }

  static Future<void> _migrateToV7(Database db) async {
    await _ensureColumn(db, 'artists', 'topicChannelId', 'TEXT');
  }

  static Future<void> _migrateToV8(Database db) async {
    await _ensureColumn(db, 'tracks', 'bitrate', 'INTEGER DEFAULT 128');
  }

  static Future<void> _migrateToV9(Database db) async {
    await _ensureColumn(db, 'tracks', 'artistAvatarUrl', 'TEXT DEFAULT ""');
  }

  /// Adds [column] to [table] during versioned migration.
  static Future<void> _ensureColumn(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  /// Seeds the initial mock tracks exactly once on a fresh database. Guarded by
  /// an empty-count check so upgrades or repeated opens never duplicate data.
  static Future<void> _seedMockTracksIfEmpty(Database db) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM tracks');
    final count = (rows.isNotEmpty ? (rows.first['c'] as int?) : 0) ?? 0;
    if (count == 0 && mockTracks.isNotEmpty) {
      final batch = db.batch();
      for (final track in mockTracks) {
        batch.insert('tracks', _trackToMap(track));
      }
      await batch.commit(noResult: true);
    }
    await _seedMockPlaylistsIfEmpty(db);
  }

  static Future<void> _seedMockPlaylistsIfEmpty(Database db) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM playlists');
    final count = (rows.isNotEmpty ? (rows.first['c'] as int?) : 0) ?? 0;
    if (count > 0 || mockPlaylists.isEmpty) return;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final playlist in mockPlaylists) {
      batch.insert('playlists', {
        'id': playlist.id,
        'title': playlist.title,
        'description': playlist.description,
        'coverUrl': playlist.coverUrl,
        'createdBy': playlist.createdBy,
        'isPublic': playlist.isPublic ? 1 : 0,
        'ambientColor': playlist.ambientColor,
        'createdAt': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      for (var i = 0; i < playlist.tracks.length; i++) {
        final track = playlist.tracks[i];
        batch.insert('tracks', _trackToMap(track), conflictAlgorithm: ConflictAlgorithm.replace);
        batch.insert('playlist_tracks', {
          'playlist_id': playlist.id,
          'track_id': track.id,
          'position': i,
        });
      }
    }
    await batch.commit(noResult: true);
  }

  static bool _ffiInitialized = false;

  DatabaseFactory _resolveFactory() {
    _setupPlatformFactory();
    if (!kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
      return databaseFactoryFfi;
    }
    return databaseFactory;
  }

  void _setupPlatformFactory([DatabaseFactory? preferred]) {
    if (preferred != null) {
      if (databaseFactoryOrNull != preferred) {
        databaseFactory = preferred;
      }
      return;
    }
    if (!kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
      if (!_ffiInitialized) {
        sqfliteFfiInit();
        _ffiInitialized = true;
      }
    }
  }

  static Map<String, dynamic> _trackToMap(Track track) {
    return {
      'id': track.id,
      'title': track.title,
      'artist': track.artist,
      'artistId': track.artistId,
      'album': track.album,
      'albumId': track.albumId,
      'duration': track.duration,
      'coverUrl': track.coverUrl,
      'audioUrl': track.audioUrl,
      'localFilePath': track.localFilePath,
      'isDownloaded': track.isDownloaded ? 1 : 0,
      'isFavorite': track.isFavorite ? 1 : 0,
      'genre': track.genre,
      'ambientColor': track.ambientColor,
      'lyrics': track.lyrics,
      'releaseYear': track.releaseYear,
      'isExplicit': track.isExplicit ? 1 : 0,
      'source': track.source,
      'bitrate': track.bitrate,
      'artistAvatarUrl': track.artistAvatarUrl,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
  }

  Track _mapToTrack(Map<String, dynamic> map) {
    return Track(
      id: map['id'] as String,
      title: map['title'] as String,
      artist: map['artist'] as String,
      artistId: (map['artistId'] as String?) ?? '',
      album: (map['album'] as String?) ?? 'Single',
      albumId: (map['albumId'] as String?) ?? '',
      duration: (map['duration'] as int?) ?? 0,
      coverUrl: map['coverUrl'] as String,
      audioUrl: map['audioUrl'] as String,
      localFilePath: map['localFilePath'] as String?,
      isDownloaded: (map['isDownloaded'] as int?) == 1,
      isFavorite: (map['isFavorite'] as int?) == 1,
      genre: (map['genre'] as String?) ?? 'Electro',
      ambientColor: (map['ambientColor'] as String?) ?? '#EC4899',
      lyrics: map['lyrics'] as String?,
      releaseYear: (map['releaseYear'] as int?) ?? 2025,
      isExplicit: (map['isExplicit'] as int?) == 1,
      source: (map['source'] as String?) ?? 'music',
      bitrate: (map['bitrate'] as int?) ?? 0,
      artistAvatarUrl: (map['artistAvatarUrl'] as String?) ?? '',
    );
  }

  Future<List<Track>> getAllTracks() async {
    final db = await database;
    final maps = await db.query('tracks', orderBy: 'createdAt DESC');
    final tracks = maps.map(_mapToTrack).toList();

    // Verify filesystem existence for offline tracks: reset any phantom downloaded tracks
    if (!kIsWeb) {
      final List<Track> verified = [];
      for (final t in tracks) {
        if (t.isDownloaded) {
          final fileExists = t.localFilePath != null && await File(t.localFilePath!).exists();
          if (!fileExists) {
            // copyWith(localFilePath: null) would keep the old value, so rebuild
            // the track with the offline fields explicitly cleared.
            final resetTrack = Track(
              id: t.id,
              title: t.title,
              artist: t.artist,
              artistId: t.artistId,
              album: t.album,
              albumId: t.albumId,
              coverUrl: t.coverUrl,
              audioUrl: t.audioUrl,
              duration: t.duration,
              genre: t.genre,
              releaseYear: t.releaseYear,
              isExplicit: t.isExplicit,
              ambientColor: t.ambientColor,
              isDownloaded: false,
              localFilePath: null,
              isFavorite: t.isFavorite,
              lyrics: t.lyrics,
              source: t.source,
              bitrate: t.bitrate,
              artistAvatarUrl: t.artistAvatarUrl,
            );
            verified.add(resetTrack);
            // Sync database asynchronously
            unawaited(db.update('tracks', {'isDownloaded': 0, 'localFilePath': null}, where: 'id = ?', whereArgs: [t.id]));
            continue;
          }
        }
        verified.add(t);
      }
      return verified;
    }

    return tracks;
  }

  /// Searches tracks stored in the local SQLite database matching title, artist, or album.
  /// Prioritizes downloaded tracks first, then favorites.
  Future<List<Track>> searchLocalTracks(String query, {int limit = 10}) async {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return [];
    final all = await getAllTracks();
    final matches = all.where((t) {
      final title = t.title.toLowerCase();
      final artist = t.artist.toLowerCase();
      final album = t.album.toLowerCase();
      return title.contains(clean) || artist.contains(clean) || album.contains(clean);
    }).toList();

    matches.sort((a, b) {
      if (a.isDownloaded && !b.isDownloaded) return -1;
      if (!a.isDownloaded && b.isDownloaded) return 1;
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;
      final aExact = a.title.toLowerCase().startsWith(clean) || a.artist.toLowerCase().startsWith(clean);
      final bExact = b.title.toLowerCase().startsWith(clean) || b.artist.toLowerCase().startsWith(clean);
      if (aExact && !bExact) return -1;
      if (!aExact && bExact) return 1;
      return a.title.compareTo(b.title);
    });
    return matches.take(limit).toList();
  }

  Future<void> clearAllTracks({bool deleteFiles = false}) async {
    final db = await database;
    if (deleteFiles && !kIsWeb) {
      final tracks = await db.query('tracks');
      for (final row in tracks) {
        final path = row['localFilePath'] as String?;
        if (path != null) {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        }
      }
    }
    await db.delete('tracks');
  }

  /// Crée de manière idempotente les index SQLite de performance pour les tris et jointures fréquents.
  static Future<void> _ensurePerformanceIndexes(Database db) async {
    try {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_tracks_created_at ON tracks(createdAt DESC)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_tracks_artist_id ON tracks(artistId)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_tracks_album_id ON tracks(albumId)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_albums_artist_id ON albums(artistId)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_playlist_tracks_pid ON playlist_tracks(playlist_id, position)');
    } catch (_) {}
  }

  /// Supprime de la BDD les morceaux issus de recherches qui n'ont jamais été écoutés,
  /// téléchargés, mis en favoris ou ajoutés à une playlist.
  static Future<void> _cleanTransientUnlistenedTracks(Database db) async {
    try {
      await db.execute('''
        DELETE FROM tracks
        WHERE isDownloaded = 0
          AND isFavorite = 0
          AND (localFilePath IS NULL OR localFilePath = '')
          AND id NOT IN (SELECT DISTINCT track_id FROM playlist_tracks)
          AND id NOT IN ('t_1', 't_2', 't_3', 't_4', 't_5', 't_6')
      ''');
    } catch (_) {}
  }

  static Future<void> _pruneSearchCacheSafe(Database db) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.delete(
        'search_cache',
        where: 'expiresAt <= ?',
        whereArgs: [now],
      );
    } catch (_) {}
  }

  Future<void> insertOrUpdateTrack(Track track) async {
    final db = await database;
    await db.insert(
      'tracks',
      _trackToMap(track),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateTrackDownload(
    String id,
    String? localPath,
    bool isDownloaded, {
    int? bitrate,
  }) async {
    final db = await database;
    final Map<String, Object?> values = {
      'localFilePath': localPath,
      'isDownloaded': isDownloaded ? 1 : 0,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    if (bitrate != null && bitrate > 0) {
      values['bitrate'] = bitrate;
    }
    await db.update(
      'tracks',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateTrackBitrate(String id, int bitrate) async {
    if (bitrate <= 0) return;
    final db = await database;
    await db.update(
      'tracks',
      {'bitrate': bitrate},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> toggleFavorite(String id, bool isFavorite) async {
    final db = await database;
    await db.update(
      'tracks',
      {'isFavorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteTrack(String id) async {
    final db = await database;
    await db.delete('tracks', where: 'id = ?', whereArgs: [id]);
  }

  // --- Artist SQLite Persistence ---

  Future<void> saveArtist(Artist artist) async {
    final db = await database;
    await db.insert(
      'artists',
      {
        'id': artist.id,
        'name': artist.name,
        'avatarUrl': artist.avatarUrl,
        'bannerUrl': artist.bannerUrl,
        'topicChannelId': artist.topicChannelId,
        'bio': artist.bio,
        'isFollowing': artist.isFollowing ? 1 : 0,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertOrUpdateArtist(Artist artist) => saveArtist(artist);

  Future<Artist?> getArtist(String id) async {
    final db = await database;
    final maps = await db.query('artists', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    final map = maps.first;
    return Artist(
      id: map['id'] as String,
      name: map['name'] as String,
      avatarUrl: (map['avatarUrl'] as String?) ?? '',
      bannerUrl: (map['bannerUrl'] as String?) ?? '',
      topicChannelId: (map['topicChannelId'] as String?) ?? '',
      bio: (map['bio'] as String?) ?? '',
      isFollowing: (map['isFollowing'] as int?) == 1,
      tracks: [],
      albums: [],
    );
  }

  Future<Artist?> findArtistByName(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return null;
    try {
      final db = await database;
      final maps = await db.query(
        'artists',
        where: 'LOWER(name) = ?',
        whereArgs: [clean.toLowerCase()],
        limit: 1,
      );
      if (maps.isNotEmpty) {
        final map = maps.first;
        return Artist(
          id: map['id'] as String,
          name: map['name'] as String,
          avatarUrl: (map['avatarUrl'] as String?) ?? '',
          bannerUrl: (map['bannerUrl'] as String?) ?? '',
          topicChannelId: (map['topicChannelId'] as String?) ?? '',
          bio: (map['bio'] as String?) ?? '',
          isFollowing: (map['isFollowing'] as int?) == 1,
          tracks: [],
          albums: [],
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Database] findArtistByName error: $e');
    }

    // Fallback recherche accentée dans la base locale + mockArtists
    try {
      final normName = FuzzyMatcher.normalize(clean);
      final all = await getAllArtists();
      for (final artist in [...mockArtists, ...all]) {
        if (FuzzyMatcher.normalize(artist.name) == normName) return artist;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Database] findArtistByName fallback error: $e');
    }

    return null;
  }

  Future<List<Artist>> getAllArtists() async {
    final db = await database;
    final maps = await db.query('artists', orderBy: 'createdAt DESC');
    return maps.map((map) {
      return Artist(
        id: map['id'] as String,
        name: map['name'] as String,
        avatarUrl: (map['avatarUrl'] as String?) ?? '',
        bannerUrl: (map['bannerUrl'] as String?) ?? '',
        topicChannelId: (map['topicChannelId'] as String?) ?? '',
        bio: (map['bio'] as String?) ?? '',
        isFollowing: (map['isFollowing'] as int?) == 1,
        tracks: [],
        albums: [],
      );
    }).toList();
  }

  Future<void> saveArtistIndex(
    String artistName, {
    String? artistId,
    String? topicChannelId,
    String? avatarUrl,
  }) async {
    final cleanName = artistName.trim();
    if (cleanName.isEmpty) return;
    final db = await database;
    final existing = await findArtistByName(cleanName);
    final finalId = (artistId != null && artistId.isNotEmpty)
        ? artistId
        : (existing != null && existing.id.isNotEmpty
            ? existing.id
            : cleanName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_'));
    final finalTopicId = (topicChannelId != null && topicChannelId.isNotEmpty)
        ? topicChannelId
        : (existing?.topicChannelId ?? '');
    final finalAvatar = (avatarUrl != null && avatarUrl.isNotEmpty)
        ? avatarUrl
        : (existing?.avatarUrl ?? '');

    await db.insert(
      'artists',
      {
        'id': finalId,
        'name': existing?.name ?? cleanName,
        'avatarUrl': finalAvatar,
        'bannerUrl': existing?.bannerUrl ?? '',
        'topicChannelId': finalTopicId,
        'bio': existing?.bio ?? '',
        'isFollowing': existing?.isFollowing == true ? 1 : 0,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveAlbumsIndex(List<Album> albums) async {
    if (albums.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final album in albums) {
      if (album.id.isEmpty || album.title.isEmpty) continue;
      batch.insert(
        'albums',
        {
          'id': album.id,
          'title': album.title,
          'artist': album.artist,
          'artistId': album.artistId,
          'coverUrl': album.coverUrl,
          'releaseYear': album.releaseYear,
          'tracksCount': album.tracksCount,
          'genre': album.genre,
          'collectionType': album.collectionType.wireName,
          'ambientColor': album.ambientColor,
          'createdAt': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> saveTracksIndex(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final track in tracks) {
      if (track.id.isEmpty || track.title.isEmpty) continue;
      batch.rawInsert('''
        INSERT INTO tracks (
          id, title, artist, artistId, album, albumId, duration, coverUrl, audioUrl,
          genre, ambientColor, releaseYear, isExplicit, source, bitrate, artistAvatarUrl, isDownloaded, isFavorite, createdAt
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, ?)
        ON CONFLICT(id) DO UPDATE SET
          title = excluded.title,
          artist = excluded.artist,
          artistId = CASE WHEN excluded.artistId != '' THEN excluded.artistId ELSE tracks.artistId END,
          album = CASE WHEN excluded.album != '' AND excluded.album != 'Single' THEN excluded.album ELSE tracks.album END,
          albumId = CASE WHEN excluded.albumId != '' THEN excluded.albumId ELSE tracks.albumId END,
          coverUrl = CASE WHEN excluded.coverUrl != '' THEN excluded.coverUrl ELSE tracks.coverUrl END,
          audioUrl = CASE WHEN excluded.audioUrl != '' THEN excluded.audioUrl ELSE tracks.audioUrl END,
          duration = CASE WHEN excluded.duration > 0 THEN excluded.duration ELSE tracks.duration END,
          source = excluded.source,
          bitrate = CASE WHEN excluded.bitrate > 0 THEN excluded.bitrate ELSE tracks.bitrate END,
          artistAvatarUrl = CASE WHEN excluded.artistAvatarUrl != '' THEN excluded.artistAvatarUrl ELSE tracks.artistAvatarUrl END
      ''', [
        track.id,
        track.title,
        track.artist,
        track.artistId,
        track.album,
        track.albumId,
        track.duration,
        track.coverUrl,
        track.audioUrl,
        track.genre,
        track.ambientColor,
        track.releaseYear,
        track.isExplicit ? 1 : 0,
        track.source,
        track.bitrate,
        track.artistAvatarUrl,
        now,
      ]);
    }
    await batch.commit(noResult: true);
  }

  
  Future<void> saveRawImportBatch(List<Track> tracks, List<Album> albums, List<Artist> artists) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final artist in artists) {
      batch.rawInsert('''
        INSERT INTO artists (id, name, avatarUrl, bannerUrl, bio, createdAt)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          name = excluded.name,
          avatarUrl = CASE WHEN excluded.avatarUrl != '' THEN excluded.avatarUrl ELSE avatarUrl END
      ''', [artist.id, artist.name, artist.avatarUrl, artist.bannerUrl, artist.bio, now]);
    }

    for (final album in albums) {
      batch.rawInsert('''
        INSERT INTO albums (id, title, artist, artistId, coverUrl, releaseYear, tracksCount, genre, ambientColor, collectionType, createdAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          title = excluded.title,
          coverUrl = CASE WHEN excluded.coverUrl != '' THEN excluded.coverUrl ELSE coverUrl END
      ''', [album.id, album.title, album.artist, album.artistId, album.coverUrl, album.releaseYear, album.tracksCount, album.genre, album.ambientColor, album.collectionType.wireName, now]);
    }

    for (final track in tracks) {
      batch.rawInsert('''
        INSERT INTO tracks (
          id, title, artist, artistId, album, albumId, duration, coverUrl, audioUrl,
          genre, ambientColor, releaseYear, isExplicit, source, bitrate, artistAvatarUrl, isDownloaded, isFavorite, createdAt
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 1, ?)
        ON CONFLICT(id) DO UPDATE SET
          title = excluded.title,
          source = excluded.source,
          isFavorite = 1
      ''', [track.id, track.title, track.artist, track.artistId, track.album, track.albumId, track.duration, track.coverUrl, track.audioUrl, track.genre, track.ambientColor, track.releaseYear, track.isExplicit ? 1 : 0, track.source, track.bitrate, track.artistAvatarUrl, now]);
    }

    await batch.commit(noResult: true);
  }

  Future<Artist?> findArtistInQuery(String query) async {
    final cleanQuery = FuzzyMatcher.normalize(query);
    if (cleanQuery.isEmpty) return null;
    final queryTokens = cleanQuery.split(' ').where((w) => w.isNotEmpty).toList();

    final all = await getAllArtists();
    final candidates = <Artist>[...mockArtists, ...all];
    candidates.sort((a, b) => b.name.length.compareTo(a.name.length));

    for (final artist in candidates) {
      final aName = FuzzyMatcher.normalize(artist.name);
      if (aName.length < 2) continue;
      if (_queryContainsArtistName(queryTokens, aName)) {
        return artist;
      }
    }

    return null;
  }

  /// Word-boundary matching: short artist names ("Art") never match inside
  /// unrelated words ("party"), accented variants are folded, and multi-word
  /// artists require a contiguous run of query tokens (or all tokens present).
  static bool _queryContainsArtistName(List<String> queryTokens, String artistName) {
    final artistTokens = artistName.split(' ').where((w) => w.isNotEmpty).toList();
    if (artistTokens.isEmpty) return false;

    if (artistTokens.length > 1) {
      for (int i = 0; i + artistTokens.length <= queryTokens.length; i++) {
        bool match = true;
        for (int j = 0; j < artistTokens.length; j++) {
          if (queryTokens[i + j] != artistTokens[j]) {
            match = false;
            break;
          }
        }
        if (match) return true;
      }
      return artistTokens.every(queryTokens.contains);
    }

    return queryTokens.contains(artistName);
  }

  Future<List<Album>> getAlbumsForArtist(String artistName, {String? artistId}) async {
    final cleanName = artistName.trim().toLowerCase();
    final cleanId = artistId?.trim() ?? '';
    final db = await database;
    List<Map<String, dynamic>> maps;

    if (cleanId.isNotEmpty) {
      maps = await db.query(
        'albums',
        where: 'artistId = ? OR LOWER(artist) = ?',
        whereArgs: [cleanId, cleanName],
        orderBy: 'releaseYear DESC, createdAt DESC',
      );
    } else {
      maps = await db.query(
        'albums',
        where: 'LOWER(artist) = ?',
        whereArgs: [cleanName],
        orderBy: 'releaseYear DESC, createdAt DESC',
      );
    }

    return maps.map((map) {
      return Album(
        id: map['id'] as String,
        title: map['title'] as String,
        artist: map['artist'] as String,
        artistId: (map['artistId'] as String?) ?? '',
        coverUrl: (map['coverUrl'] as String?) ?? '',
        releaseYear: (map['releaseYear'] as int?) ?? 2025,
        tracksCount: (map['tracksCount'] as int?) ?? 0,
        genre: (map['genre'] as String?) ?? 'Album',
        collectionType: CollectionType.fromWire(map['collectionType'], legacyGenre: map['genre'] as String?),
        ambientColor: (map['ambientColor'] as String?) ?? '401E293B',
        tracks: [],
      );
    }).toList();
  }

  // --- Album SQLite Persistence ---

  Future<void> insertOrUpdateAlbum(Album album) async {
    final db = await database;
    await db.insert(
      'albums',
      {
        'id': album.id,
        'title': album.title,
        'artist': album.artist,
        'artistId': album.artistId,
        'coverUrl': album.coverUrl,
        'releaseYear': album.releaseYear,
        'tracksCount': album.tracksCount,
        'genre': album.genre,
        'collectionType': album.collectionType.wireName,
        'ambientColor': album.ambientColor,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Album?> getAlbum(String id) async {
    final db = await database;
    final maps = await db.query('albums', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    final map = maps.first;
    return Album(
      id: map['id'] as String,
      title: map['title'] as String,
      artist: map['artist'] as String,
      artistId: (map['artistId'] as String?) ?? '',
      coverUrl: (map['coverUrl'] as String?) ?? '',
      releaseYear: (map['releaseYear'] as int?) ?? 2025,
      tracksCount: (map['tracksCount'] as int?) ?? 0,
      genre: (map['genre'] as String?) ?? '',
      collectionType: CollectionType.fromWire(map['collectionType'], legacyGenre: map['genre'] as String?),
      ambientColor: (map['ambientColor'] as String?) ?? '#8B5CF6',
      tracks: [],
    );
  }

  Future<List<Album>> getAllAlbums() async {
    final db = await database;
    final maps = await db.query('albums', orderBy: 'createdAt DESC');
    return maps.map((map) {
      return Album(
        id: map['id'] as String,
        title: map['title'] as String,
        artist: map['artist'] as String,
        artistId: (map['artistId'] as String?) ?? '',
        coverUrl: (map['coverUrl'] as String?) ?? '',
        releaseYear: (map['releaseYear'] as int?) ?? 2025,
        tracksCount: (map['tracksCount'] as int?) ?? 0,
      genre: (map['genre'] as String?) ?? '',
      collectionType: CollectionType.fromWire(map['collectionType'], legacyGenre: map['genre'] as String?),
      ambientColor: (map['ambientColor'] as String?) ?? '#8B5CF6',
        tracks: [],
      );
    }).toList();
  }

  Future<List<Album>> getAlbumsByArtistId(String artistId) async {
    final db = await database;
    final maps = await db.query('albums', where: 'artistId = ?', whereArgs: [artistId], orderBy: 'releaseYear DESC');
    return maps.map((map) {
      return Album(
        id: map['id'] as String,
        title: map['title'] as String,
        artist: map['artist'] as String,
        artistId: (map['artistId'] as String?) ?? '',
        coverUrl: (map['coverUrl'] as String?) ?? '',
        releaseYear: (map['releaseYear'] as int?) ?? 2025,
        tracksCount: (map['tracksCount'] as int?) ?? 0,
        genre: (map['genre'] as String?) ?? '',
        collectionType: CollectionType.fromWire(map['collectionType'], legacyGenre: map['genre'] as String?),
        ambientColor: (map['ambientColor'] as String?) ?? '#8B5CF6',
        tracks: [],
      );
    }).toList();
  }

  Future<List<Album>> getAlbumsByArtist(String artistName, {String artistId = ''}) async {
    final db = await database;
    final clean = artistName.trim().toLowerCase();
    final maps = await db.query(
      'albums',
      where: 'LOWER(artist) = ? OR (artistId != "" AND artistId = ?)',
      whereArgs: [clean, artistId],
      orderBy: 'releaseYear DESC',
    );
    return maps.map((map) {
      return Album(
        id: map['id'] as String,
        title: map['title'] as String,
        artist: map['artist'] as String,
        artistId: (map['artistId'] as String?) ?? '',
        coverUrl: (map['coverUrl'] as String?) ?? '',
        releaseYear: (map['releaseYear'] as int?) ?? 2025,
        tracksCount: (map['tracksCount'] as int?) ?? 0,
        genre: (map['genre'] as String?) ?? '',
        collectionType: CollectionType.fromWire(map['collectionType'], legacyGenre: map['genre'] as String?),
        ambientColor: (map['ambientColor'] as String?) ?? '#8B5CF6',
        tracks: [],
      );
    }).toList();
  }

  Future<List<Playlist>> getAllPlaylists() async {
    final db = await database;
    final rows = await db.query('playlists', orderBy: 'createdAt DESC');
    if (rows.isEmpty) return const <Playlist>[];

    // Chargement groupé en une seule jointure SQL au lieu de N*M requêtes séquentielles
    final joinedRows = await db.rawQuery('''
      SELECT pt.playlist_id AS _joined_playlist_id, t.*
      FROM playlist_tracks pt
      INNER JOIN tracks t ON t.id = pt.track_id
      ORDER BY pt.playlist_id ASC, pt.position ASC
    ''');

    final tracksByPlaylist = <String, List<Track>>{};
    for (final tr in joinedRows) {
      final pid = tr['_joined_playlist_id'] as String?;
      if (pid == null) continue;
      (tracksByPlaylist[pid] ??= <Track>[]).add(_mapToTrack(tr));
    }

    final result = <Playlist>[];
    for (final row in rows) {
      final pid = row['id'] as String;
      result.add(Playlist(
        id: pid,
        title: (row['title'] as String?) ?? '',
        description: (row['description'] as String?) ?? '',
        coverUrl: (row['coverUrl'] as String?) ?? '',
        tracks: tracksByPlaylist[pid] ?? const <Track>[],
        createdBy: (row['createdBy'] as String?) ?? 'You',
        isPublic: (row['isPublic'] as int?) != 0,
        ambientColor: (row['ambientColor'] as String?) ?? '#EC4899',
      ));
    }
    return List.unmodifiable(result);
  }

  Future<Playlist> createPlaylist(String title, String description) async {
    final playlist = Playlist(
      id: 'pl_${DateTime.now().microsecondsSinceEpoch}',
      title: title.trim(),
      description: description.trim(),
      coverUrl: '',
      tracks: const [],
      createdBy: 'You',
      isPublic: true,
      ambientColor: '#EC4899',
    );
    final db = await database;
    await db.insert('playlists', {
      'id': playlist.id,
      'title': playlist.title,
      'description': playlist.description,
      'coverUrl': playlist.coverUrl,
      'createdBy': playlist.createdBy,
      'isPublic': playlist.isPublic ? 1 : 0,
      'ambientColor': playlist.ambientColor,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    return playlist;
  }

  Future<bool> addTrackToPlaylist(String playlistId, Track track) async {
    final db = await database;
    await insertOrUpdateTrack(track);
    final existing = await db.query(
      'playlist_tracks',
      where: 'playlist_id = ? AND track_id = ?',
      whereArgs: [playlistId, track.id],
      limit: 1,
    );
    if (existing.isNotEmpty) return false;
    final positionRows = await db.rawQuery(
      'SELECT COALESCE(MAX(position), -1) + 1 AS nextPosition FROM playlist_tracks WHERE playlist_id = ?',
      [playlistId],
    );
    final position = (positionRows.first['nextPosition'] as int?) ?? 0;
    await db.insert('playlist_tracks', {
      'playlist_id': playlistId,
      'track_id': track.id,
      'position': position,
    });
    return true;
  }

  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async {
    final db = await database;
    await db.delete('playlist_tracks', where: 'playlist_id = ? AND track_id = ?', whereArgs: [playlistId, trackId]);
  }

  Future<void> deletePlaylist(String playlistId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('playlist_tracks', where: 'playlist_id = ?', whereArgs: [playlistId]);
      await txn.delete('playlists', where: 'id = ?', whereArgs: [playlistId]);
    });
  }

  /// Reads one persistent search payload when it is still inside its TTL.
  /// The payload is intentionally opaque JSON: callers keep all raw text and
  /// network identifiers without forcing them through model-specific columns.
  Future<String?> readSearchCache(String cacheKey) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await db.query(
      'search_cache',
      columns: ['payload'],
      where: 'cacheKey = ? AND expiresAt > ?',
      whereArgs: [cacheKey, now],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['payload'] as String?;
  }

  Future<void> writeSearchCache({
    required String cacheKey,
    required String cacheType,
    required String queryText,
    required String payload,
    required Duration ttl,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'search_cache',
      {
        'cacheKey': cacheKey,
        'cacheType': cacheType,
        'queryText': queryText,
        'payload': payload,
        'expiresAt': now + ttl.inMilliseconds,
        'createdAt': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> pruneSearchCache() async {
    final db = await database;
    await db.delete(
      'search_cache',
      where: 'expiresAt <= ?',
      whereArgs: [DateTime.now().millisecondsSinceEpoch],
    );
  }

  /// Retrieves the most recent unique search queries, sorted newest first
  Future<List<String>> getSearchHistory({int limit = 8}) async {
    final db = await database;
    final rows = await db.query(
      'search_history',
      columns: ['query'],
      orderBy: 'createdAt DESC, id DESC',
      limit: limit * 2,
    );
    final Set<String> seen = {};
    final List<String> result = [];
    for (final row in rows) {
      final q = (row['query'] as String?)?.trim() ?? '';
      if (q.isNotEmpty && !seen.contains(q.toLowerCase())) {
        seen.add(q.toLowerCase());
        result.add(q);
        if (result.length >= limit) break;
      }
    }
    return result;
  }

  /// Adds or updates a search query in the search history
  Future<void> addSearchHistory(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Delete existing identical (case-insensitive) queries to deduplicate
    await db.delete(
      'search_history',
      where: 'LOWER(query) = ?',
      whereArgs: [clean.toLowerCase()],
    );
    searchHistoryGeneration.value++;

    // Insert new entry with current timestamp
    await db.insert('search_history', {
      'query': clean,
      'createdAt': now,
    });

    // Prune history to keep at most 20 entries
    await db.execute('''
      DELETE FROM search_history
      WHERE id NOT IN (
        SELECT id FROM search_history
        ORDER BY createdAt DESC, id DESC
        LIMIT 20
      )
    ''');
  }

  /// Removes a single query from the search history
  Future<void> removeSearchHistory(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;
    final db = await database;
    await db.delete(
      'search_history',
      where: 'LOWER(query) = ?',
      whereArgs: [clean.toLowerCase()],
    );
    searchHistoryGeneration.value++;
  }

  /// Clears the entire search history
  Future<void> clearSearchHistory() async {
    final db = await database;
    await db.delete('search_history');
    searchHistoryGeneration.value++;
  }

  Future<void> clearAllData() async {
    final db = await database;
    for (final table in ['tracks', 'albums', 'artists', 'playlists', 'playlist_tracks', 'search_history', 'search_cache']) {
      await db.delete(table);
    }
    searchHistoryGeneration.value++;
  }

  Future<void> close() async {
    final db = await _dbFuture;
    _dbFuture = null;
    if (db != null) {
      await db.close();
    }
  }
}
