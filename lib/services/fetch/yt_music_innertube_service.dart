import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../models/album.dart';
import '../database_service.dart';
import '../network/network_exception.dart';
import '../network/network_guard.dart';
import 'yt_utils.dart';

/// Specialized service for YouTube Music InnerTube API requests (Official Artists, Albums, Discographies)
class YtMusicInnertubeService {
  final YoutubeExplode _client;
  final BrowserHttpClient _httpClient;

  YtMusicInnertubeService({
    YoutubeExplode? client,
    BrowserHttpClient? httpClient,
  })  : _client = client ?? YoutubeExplode(),
        _httpClient = httpClient ?? BrowserHttpClient();

  // LRU Channel / Artist Details Cache
  final Map<String, ({String title, String logoUrl, String bannerUrl})> _channelCache = {};

  // LRU Artist Releases & Playlists Cache
  final Map<String, ({List<Album> releases, List<Album> playlists})> _artistDiscographyCache = {};

  void clearCache() {
    _channelCache.clear();
    _artistDiscographyCache.clear();
  }

  static const Map<String, String> _ytHeaders = {
    'Content-Type': 'application/json',
    'X-YouTube-Client-Name': '67',
    'X-YouTube-Client-Version': '1.20250101.01.00',
    'Origin': 'https://music.youtube.com',
  };

  /// Posts to the YouTube Music InnerTube API, raising a typed [NetworkException]
  /// on timeout / connectivity failures instead of silently swallowing them.
  Future<http.Response> _postYT(String path, String body,
      {Duration timeout = const Duration(seconds: 6)}) async {
    try {
      final res = await _httpClient
          .post(Uri.parse('https://music.youtube.com$path'),
              headers: _ytHeaders, body: body)
          .timeout(timeout);
      return NetworkGuard.ensureSuccess(res);
    } on TimeoutException {
      throw const NetworkTimeoutException();
    } on NetworkException {
      rethrow;
    } on SocketException catch (e) {
      throw NetworkUnavailableException(e.message);
    } on http.ClientException catch (e) {
      throw NetworkUnavailableException(e.message);
    }
  }

  /// Retrieve separated releases and playlists strictly tied to an artist's official catalog
  Future<({List<Album> releases, List<Album> playlists})> getArtistReleasesAndPlaylists(
    String artistName, {
    String artistId = '',
    int limit = 12,
  }) async {
    final cleanName = artistName.trim();
    if (cleanName.isEmpty) return (releases: <Album>[], playlists: <Album>[]);

    final cacheKey = cleanName.toLowerCase();
    if (_artistDiscographyCache.containsKey(cacheKey)) {
      return _artistDiscographyCache[cacheKey]!;
    }

    try {
      final List<Album> releases = [];
      final List<Album> playlists = [];
      final Set<String> seenIds = {};

      // 1. Interroger YouTube Music InnerTube pour trouver l'ID officiel de l'artiste
      String? artistBrowseId;
      final searchBody = jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20240101.01.00',
            'hl': 'en',
            'gl': 'US',
          }
        },
        'query': cleanName,
      });
      final searchRes = await _postYT('/youtubei/v1/search', searchBody, timeout: const Duration(seconds: 5));
      final searchJson = NetworkGuard.decodeJsonObject(searchRes);
      final contents = searchJson['contents']?['tabbedSearchResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents'] as List? ?? [];

      for (final s in contents) {
        if (s is Map<String, dynamic>) {
          // 1. Check musicCardShelfRenderer (Top result card for artist)
          final card = s['musicCardShelfRenderer'];
          if (card != null) {
            final nav = card['title']?['runs']?[0]?['navigationEndpoint'] ?? card['navigationEndpoint'];
            final bId = nav?['browseEndpoint']?['browseId'] as String?;
            if (bId != null && bId.isNotEmpty) {
              artistBrowseId = bId;
              break;
            }
          }

          // 2. Check musicShelfRenderer items
          final items = s['musicShelfRenderer']?['contents'] as List? ?? [];
          for (final it in items) {
            final flex = it['musicResponsiveListItemRenderer']?['flexColumns'] as List? ?? [];
            for (final col in flex) {
              final runs = col['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List? ?? [];
              for (final r in runs) {
                final nav = r['navigationEndpoint']?['browseEndpoint'];
                final bId = nav?['browseId'] as String?;
                final pageType = nav?['browseEndpointContextSupportedConfigs']?['browseEndpointContextMusicConfig']?['pageType'] as String?;
                if (bId != null && pageType == 'MUSIC_PAGE_TYPE_ARTIST') {
                  artistBrowseId = bId;
                  break;
                }
              }
              if (artistBrowseId != null) break;
            }
            if (artistBrowseId != null) break;

            final navEndpoint = it['musicResponsiveListItemRenderer']?['navigationEndpoint'];
            final bId = navEndpoint?['browseEndpoint']?['browseId'] as String?;
            final pageType = navEndpoint?['browseEndpoint']?['browseEndpointContextSupportedConfigs']?['browseEndpointContextMusicConfig']?['pageType'] as String?;
            if (bId != null && pageType == 'MUSIC_PAGE_TYPE_ARTIST') {
              artistBrowseId = bId;
              break;
            }
          }
        }
        if (artistBrowseId != null) break;
      }

      // 2. Si l'artiste a été trouvé sur YouTube Music, récupérer ses sorties officielles
      String extractedAvatar = '';
      if (artistBrowseId != null) {
        final browseBody = jsonEncode({
          'context': {
            'client': {
              'clientName': 'WEB_REMIX',
              'clientVersion': '1.20240101.01.00',
              'hl': 'en',
              'gl': 'US',
            }
          },
          'browseId': artistBrowseId,
        });
        final browseRes = await _postYT('/youtubei/v1/browse', browseBody);
        final browseJson = NetworkGuard.decodeJsonObject(browseRes);

        // Extraire la bannière et l'avatar HD de l'artiste depuis le header de YouTube Music
        final header = browseJson['header'];
        final visualHeader = header?['musicVisualHeaderRenderer'] ??
            header?['musicImmersiveHeaderRenderer'] ??
            header?['musicHeaderRenderer'];
        if (visualHeader != null) {
          final bannerThumbs = visualHeader['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List? ?? [];
          var avatarThumbs = visualHeader['foregroundThumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List? ?? [];
          if (avatarThumbs.isEmpty) {
            avatarThumbs = visualHeader['avatar']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List? ?? [];
          }
          if (avatarThumbs.isEmpty) {
            avatarThumbs = visualHeader['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List? ?? [];
          }
          String banner = bannerThumbs.isNotEmpty ? bannerThumbs.last['url'] as String? ?? '' : '';
          String avatar = avatarThumbs.isNotEmpty ? avatarThumbs.last['url'] as String? ?? '' : '';

          if (banner.contains('=')) {
            banner = banner.split('=')[0] + '=w2880-h1200-l90-rj';
          }
          if (avatar.contains('=')) {
            avatar = avatar.split('=')[0] + '=w600-h600-l90-rj';
          }

          extractedAvatar = avatar;

          if (avatar.isNotEmpty || banner.isNotEmpty) {
            final cacheEntry = (
              title: cleanName,
              logoUrl: avatar,
              bannerUrl: banner,
            );
            _channelCache[cleanName.toLowerCase()] = cacheEntry;
            if (artistBrowseId.isNotEmpty) {
              _channelCache[artistBrowseId] = cacheEntry;
            }
            if (artistId.isNotEmpty) {
              _channelCache[artistId.toLowerCase()] = cacheEntry;
            }
          }
        }

        final sections = browseJson['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents'] as List? ??
            browseJson['contents']?['sectionListRenderer']?['contents'] as List? ??
            [];

        for (final sec in sections) {
          final shelf = sec['musicCarouselShelfRenderer'] ?? sec['musicShelfRenderer'];
          if (shelf == null) continue;

          final headerRuns = shelf['header']?['musicCarouselShelfBasicHeaderRenderer']?['title']?['runs'] as List? ?? [];
          final sectionTitle = headerRuns.map((r) => r['text']).join('').toLowerCase();

          final isAlbumOrSingle = sectionTitle.contains('album') || sectionTitle.contains('single') || sectionTitle.contains('ep') || sectionTitle.contains('release') || sectionTitle.contains('discograph');
          final isPlaylistSection = sectionTitle.contains('playlist') || sectionTitle.contains('featured') || sectionTitle.contains('sélection') || sectionTitle.contains('mix') || sectionTitle.contains('appears on');

          void parseTwoRow(dynamic it, {required bool isAlbumOrSingle, required bool isPlaylistSection}) {
            final twoRow = it['musicTwoRowItemRenderer'];
            if (twoRow == null) return;

            final titleRuns = twoRow['title']?['runs'] as List? ?? [];
            final albumTitle = titleRuns.map((r) => r['text']).join('').trim();
            if (albumTitle.isEmpty) return;

            final nav = twoRow['navigationEndpoint']?['browseEndpoint'];
            final browseId = nav?['browseId'] as String? ?? '';
            if (browseId.isEmpty || seenIds.contains(browseId)) return;

            final subtitleRuns = twoRow['subtitle']?['runs'] as List? ?? [];
            final subtitleText = subtitleRuns.map((r) => r['text']).join(' ').toLowerCase();

            final rawLower = albumTitle.toLowerCase();
            final artistLower = cleanName.toLowerCase();
            final isArtistPlaylist = rawLower.contains(artistLower) ||
                subtitleText.contains(artistLower) ||
                sectionTitle.contains('by $artistLower');

            if (!isAlbumOrSingle && !isArtistPlaylist) {
              return;
            }

            seenIds.add(browseId);

            final thumbs = twoRow['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List? ?? [];
            String cover = thumbs.isNotEmpty ? thumbs.last['url'] as String? ?? '' : '';
            if (cover.contains('=')) {
              cover = cover.split('=')[0] + '=w600-h600-l90-rj';
            }

            int releaseYear = DateTime.now().year;
            for (final sub in subtitleRuns) {
              final txt = sub['text'] as String? ?? '';
              final y = int.tryParse(txt.trim());
              if (y != null && y > 1950 && y <= DateTime.now().year + 1) {
                releaseYear = y;
                break;
              }
            }

            final isSingle = subtitleRuns.any((r) => (r['text'] as String? ?? '').toLowerCase().contains('single'));
            final isEP = subtitleRuns.any((r) => (r['text'] as String? ?? '').toLowerCase().contains('ep'));

            final cleanedTitle = YtUtils.cleanTitle(albumTitle, artist: cleanName);
            final albumObj = Album(
              id: browseId,
              title: cleanedTitle,
              artist: cleanName,
              artistId: artistBrowseId ?? '',
              coverUrl: cover,
              releaseYear: releaseYear,
              tracksCount: isSingle ? 1 : (isEP ? 5 : 12),
              genre: isSingle ? 'Single' : (isAlbumOrSingle ? 'Sortie Officielle' : 'Playlist Officielle'),
              ambientColor: YtUtils.pickAmbientColor(browseId),
            );

            if (isAlbumOrSingle) {
              releases.add(albumObj);
            } else if (isPlaylistSection) {
              playlists.add(albumObj);
            } else {
              releases.add(albumObj);
            }
          }

          final items = shelf['contents'] as List? ?? [];
          for (final it in items) {
            parseTwoRow(it, isAlbumOrSingle: isAlbumOrSingle, isPlaylistSection: isPlaylistSection);
          }

          // Charger la discographie intégrale via le bouton officiel "Voir tout" (More / Full Grid)
          final header = shelf['header']?['musicCarouselShelfBasicHeaderRenderer'];
          final moreEndpoint = header?['moreContentEndpoint']?['browseEndpoint'] ??
              header?['title']?['runs']?[0]?['navigationEndpoint']?['browseEndpoint'];
          final moreBrowseId = moreEndpoint?['browseId'] as String?;
          final moreParams = moreEndpoint?['params'] as String?;

          if (moreBrowseId != null && isAlbumOrSingle) {
            try {
              final moreRes = await _postYT('/youtubei/v1/browse', jsonEncode({
                'context': {
                  'client': {
                    'clientName': 'WEB_REMIX',
                    'clientVersion': '1.20240101.01.00',
                    'hl': 'en',
                    'gl': 'US',
                  }
                },
                'browseId': moreBrowseId,
                if (moreParams != null) 'params': moreParams,
              }), timeout: const Duration(seconds: 5));
              final moreJson = NetworkGuard.decodeJsonObject(moreRes);
              final gridItems = moreJson['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']?[0]?['gridRenderer']?['items'] as List? ??
                  moreJson['contents']?['sectionListRenderer']?['contents']?[0]?['gridRenderer']?['items'] as List? ??
                  [];
              for (final git in gridItems) {
                parseTwoRow(git, isAlbumOrSingle: isAlbumOrSingle, isPlaylistSection: false);
              }
            } catch (_) {}
          }
        }
      }

      // 2b. Même moteur : Découverte des albums officiels associés aux titres phares de l'artiste
      final queriesToSearch = [cleanName, '$cleanName album', '$cleanName mixtape'];
      for (final q in queriesToSearch) {
        try {
          final artistTracksSearch = await _postYT('/youtubei/v1/search', jsonEncode({
            'context': {
              'client': {
                'clientName': 'WEB_REMIX',
                'clientVersion': '1.20240101.01.00',
                'hl': 'en',
                'gl': 'FR',
              }
            },
            'query': q,
            'params': 'EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D', // Tracks filter
          }), timeout: const Duration(seconds: 4));
          final searchJson = NetworkGuard.decodeJsonObject(artistTracksSearch);

          void extractTrackAlbums(dynamic obj) {
            if (obj is Map<String, dynamic>) {
              if (obj.containsKey('musicResponsiveListItemRenderer')) {
                final renderer = obj['musicResponsiveListItemRenderer'];
                final flexColumns = renderer['flexColumns'] as List<dynamic>? ?? [];

                String trackArtist = '';
                String albumTitle = '';
                String albumBrowseId = '';

                if (flexColumns.length > 1) {
                  final runs = flexColumns[1]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List<dynamic>?;
                  if (runs != null && runs.isNotEmpty) {
                    trackArtist = runs[0]['text'] ?? '';
                    for (final r in runs) {
                      final nav = r['navigationEndpoint']?['browseEndpoint']?['browseId'] as String?;
                      if (nav != null && (nav.startsWith('MPREb_') || nav.startsWith('OLAK5uy_') || nav.startsWith('VL') || nav.startsWith('PL'))) {
                        albumBrowseId = nav;
                        albumTitle = r['text'] ?? '';
                      }
                    }
                  }
                }

                if (flexColumns.length > 2) {
                  final runs = flexColumns[2]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List<dynamic>?;
                  if (runs != null && runs.isNotEmpty) {
                    for (final r in runs) {
                      final nav = r['navigationEndpoint']?['browseEndpoint']?['browseId'] as String?;
                      if (nav != null && (nav.startsWith('MPREb_') || nav.startsWith('OLAK5uy_') || nav.startsWith('VL') || nav.startsWith('PL'))) {
                        albumBrowseId = nav;
                        albumTitle = r['text'] ?? '';
                        break;
                      }
                    }
                  }
                }

                // Si le morceau appartient bien à cet artiste et pointe vers un vrai album
                if (trackArtist.toLowerCase().contains(cleanName.toLowerCase()) &&
                    albumBrowseId.isNotEmpty &&
                    albumTitle.isNotEmpty &&
                    albumTitle != 'Single' &&
                    albumTitle != 'Single Web' &&
                    !seenIds.contains(albumBrowseId)) {
                  seenIds.add(albumBrowseId);

                  final thumbs = renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List<dynamic>? ?? [];
                  String cover = thumbs.isNotEmpty ? thumbs.last['url'] as String? ?? '' : '';
                  if (cover.contains('=')) {
                    cover = cover.split('=')[0] + '=w600-h600-l90-rj';
                  }

                  releases.add(Album(
                    id: albumBrowseId,
                    title: YtUtils.cleanTitle(albumTitle, artist: cleanName),
                    artist: cleanName,
                    artistId: artistBrowseId ?? '',
                    coverUrl: cover,
                    releaseYear: DateTime.now().year,
                    tracksCount: 12,
                    genre: 'Sortie Officielle',
                    ambientColor: YtUtils.pickAmbientColor(albumBrowseId),
                  ));
                }
                return;
              }
              for (final v in obj.values) extractTrackAlbums(v);
            } else if (obj is List<dynamic>) {
              for (final item in obj) extractTrackAlbums(item);
            }
          }

          extractTrackAlbums(searchJson);
        } catch (_) {}
      }

      // 2c. Fusionner les albums de cet artiste déjà découverts dans la base SQLite locale
      try {
        final localAlbums = await DatabaseService.instance.getAlbumsByArtist(cleanName, artistId: artistBrowseId ?? '');
        for (final loc in localAlbums) {
          if (!seenIds.contains(loc.id)) {
            seenIds.add(loc.id);
            releases.add(loc);
          }
        }
      } catch (_) {}

      // Persister l'artiste en base SQLite
      if (artistBrowseId != null) {
        unawaited(DatabaseService.instance.saveArtistIndex(
          cleanName,
          artistId: artistBrowseId,
          avatarUrl: extractedAvatar,
        ));
      }

      // 3. Fallback standard YouTube si YouTube Music n'a rien renvoyé
      if (releases.isEmpty && playlists.isEmpty) {
        final ytSearch = await NetworkGuard.retryWithBackoff<List<SearchResult>>(
          operation: () async {
            try {
              return await _client.search
                  .searchContent('$cleanName Official Album', filter: TypeFilters.playlist)
                  .timeout(const Duration(seconds: 6))
                  .then((v) => v.toList());
            } on TimeoutException {
              throw const NetworkTimeoutException();
            } on SocketException catch (e) {
              throw NetworkUnavailableException(e.message);
            } on http.ClientException catch (e) {
              throw NetworkUnavailableException(e.message);
            }
          },
          maxAttempts: 2,
        );

        for (final item in ytSearch) {
          if (item is SearchPlaylist && !seenIds.contains(item.id.value)) {
            seenIds.add(item.id.value);
            final title = item.title.trim();
            final isRelease = item.videoCount <= 28;

            final alb = Album(
              id: item.id.value,
              title: title,
              artist: cleanName,
              artistId: artistId,
              coverUrl: item.thumbnails.isNotEmpty ? item.thumbnails.last.url.toString() : '',
              releaseYear: DateTime.now().year,
              tracksCount: item.videoCount,
              genre: isRelease ? 'Sortie Officielle' : 'Playlist Artiste',
              ambientColor: YtUtils.pickAmbientColor(item.id.value),
            );

            if (isRelease) {
              releases.add(alb);
            } else {
              playlists.add(alb);
            }
          }
        }
      }

      // 4. Résolution en parallèle du vrai nombre de morceaux (tracksCount)
      final allItems = [...releases, ...playlists];
      if (allItems.isNotEmpty) {
        final counts = await Future.wait(
          allItems.map((alb) async {
            if (alb.genre == 'Single') return 1;
            final count = await _resolveExactTrackCount(alb.id);
            return count > 0 ? count : alb.tracksCount;
          }),
        );

        final updatedReleases = <Album>[];
        for (int i = 0; i < releases.length; i++) {
          final count = counts[i];
          updatedReleases.add(releases[i].copyWith(tracksCount: count));
        }

        final updatedPlaylists = <Album>[];
        for (int i = 0; i < playlists.length; i++) {
          final count = counts[releases.length + i];
          updatedPlaylists.add(playlists[i].copyWith(tracksCount: count));
        }

        releases
          ..clear()
          ..addAll(updatedReleases);
        playlists
          ..clear()
          ..addAll(updatedPlaylists);
      }

      final result = (releases: releases, playlists: playlists);
      if (_artistDiscographyCache.length >= 40) {
        _artistDiscographyCache.remove(_artistDiscographyCache.keys.first);
      }
      _artistDiscographyCache[cacheKey] = result;
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('[Innertube] Error fetching releases: $e');
      if (e is NetworkException) rethrow;
      return (releases: <Album>[], playlists: <Album>[]);
    }
  }

  /// Résout le nombre réel et exact de pistes d'un album ou d'une playlist
  Future<int> _resolveExactTrackCount(String rawId) async {
    try {
      final cleanPlId = rawId.startsWith('VL') ? rawId.substring(2) : rawId;
      if (cleanPlId.startsWith('PL') || cleanPlId.startsWith('OLAK5uy_')) {
        final pl = await _client.playlists.get(cleanPlId).timeout(const Duration(seconds: 4));
        if (pl.videoCount != null && pl.videoCount! > 0) {
          return pl.videoCount!;
        }
      }

      final browseId = rawId.startsWith('VL') || rawId.startsWith('MPREb_') ? rawId : 'VL$cleanPlId';
      final albBody = jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20240101.01.00',
            'hl': 'en',
            'gl': 'US',
          }
        },
        'browseId': browseId,
      });
      final albRes = await _postYT('/youtubei/v1/browse', albBody, timeout: const Duration(seconds: 4));
      if (albRes.statusCode == 200) {
        final albJson = jsonDecode(albRes.body);
        int count = 0;
        void countTracks(dynamic obj) {
          if (obj is Map) {
            if (obj.containsKey('musicResponsiveListItemRenderer')) {
              count++;
            }
            for (final v in obj.values) {
              countTracks(v);
            }
          } else if (obj is List) {
            for (final el in obj) {
              countTracks(el);
            }
          }
        }
        countTracks(albJson);
        return count;
      }
    } catch (_) {}
    return 0;
  }

  /// Get HD Channel details (Avatar, Banner, Title)
  Future<({String title, String logoUrl, String bannerUrl})?> getChannelDetails(String channelId) async {
    if (channelId.isEmpty) return null;
    if (_channelCache.containsKey(channelId)) return _channelCache[channelId];

    try {
      final channel = await _client.channels.get(channelId).timeout(const Duration(seconds: 4));
      final result = (
        title: channel.title,
        logoUrl: channel.logoUrl,
        bannerUrl: channel.bannerUrl,
      );
      if (_channelCache.length >= 60) _channelCache.remove(_channelCache.keys.first);
      _channelCache[channelId] = result;
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Get HD artist channel details by artist name or ID
  Future<({String title, String logoUrl, String bannerUrl})?> getArtistChannelDetails(
    String artistName, {
    String artistId = '',
  }) async {
    final cleanName = artistName.trim();
    final cacheKey = artistId.isNotEmpty ? artistId : cleanName.toLowerCase();
    if (_channelCache.containsKey(cacheKey) && _channelCache[cacheKey]!.logoUrl.isNotEmpty) {
      return _channelCache[cacheKey];
    }

    if (cleanName.isEmpty) return null;

    // 1. Charger la discographie YouTube Music qui extrait automatiquement la bannière HD et le logo
    try {
      await getArtistReleasesAndPlaylists(cleanName, artistId: artistId);
      if (_channelCache.containsKey(cacheKey) && _channelCache[cacheKey]!.logoUrl.isNotEmpty) {
        return _channelCache[cacheKey];
      }
      if (_channelCache.containsKey(cleanName.toLowerCase()) && _channelCache[cleanName.toLowerCase()]!.logoUrl.isNotEmpty) {
        return _channelCache[cleanName.toLowerCase()];
      }
    } catch (_) {}

    // 2. Si artistId (ex: UC...) est présent, charger les détails de la chaîne YouTube
    if (artistId.isNotEmpty && artistId.startsWith('UC')) {
      final details = await getChannelDetails(artistId);
      if (details != null && details.logoUrl.isNotEmpty) {
        _channelCache[cacheKey] = details;
        return details;
      }
    }

    // 3. Fallback: recherche de la chaîne YouTube officielle de l'artiste pour extraire son avatar HD
    try {
      final channels = await _client.search.search(cleanName, filter: TypeFilters.channel).timeout(const Duration(seconds: 3));
      if (channels.isNotEmpty) {
        final chId = channels.first.id.value;
        final details = await getChannelDetails(chId);
        if (details != null && details.logoUrl.isNotEmpty) {
          _channelCache[cacheKey] = details;
          return details;
        }
      }
    } catch (_) {}

    if (_channelCache.containsKey(cacheKey)) return _channelCache[cacheKey];
    return null;
  }
}
