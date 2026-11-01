import 'dart:async';
import 'dart:convert';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/track.dart';
import '../models/album.dart';
import '../models/search_engine_response.dart';
import 'fetch/yt_utils.dart';
import 'fetch/yt_music_innertube_service.dart';
import 'fetch/yt_stream_resolver.dart';
import 'fetch/yt_search_service.dart';
import 'database_service.dart';

export 'fetch/yt_utils.dart';
export 'fetch/yt_music_innertube_service.dart';
export 'fetch/yt_stream_resolver.dart';
export 'fetch/yt_search_service.dart';

/// Lightweight facade orchestrating specialized fetch services
class AudioFetchService {
  static final AudioFetchService instance = AudioFetchService._internal();

  final BrowserHttpClient _browserClient;
  final YoutubeExplode _client;
  final YtMusicInnertubeService _innertubeService;
  final YtStreamResolver _streamResolver;
  final YtSearchService _searchService;

  AudioFetchService._internal({
    BrowserHttpClient? browserClient,
    YoutubeExplode? client,
  })  : _browserClient = browserClient ?? BrowserHttpClient(),
        _client = client ?? YoutubeExplode(),
        _innertubeService = YtMusicInnertubeService(
          client: client,
          httpClient: browserClient,
        ),
        _streamResolver = YtStreamResolver(
          client: client,
          browserClient: browserClient,
        ),
        _searchService = YtSearchService(client: client);

  // Service Accessors
  YoutubeExplode get ytClient => _client;
  YtMusicInnertubeService get innertubeService => _innertubeService;
  YtStreamResolver get streamResolver => _streamResolver;
  YtSearchService get searchService => _searchService;

  // Utility Delegations for Backwards Compatibility
  Map<String, String> parseCleanTitleAndArtist(String rawTitle, String author) =>
      YtUtils.parseCleanTitleAndArtist(rawTitle, author);

  int parseDurationString(String durationStr) =>
      YtUtils.parseDurationString(durationStr);

  String getBestThumbnail(Video video) =>
      YtUtils.getBestThumbnail(video);

  String formatCompactViews(int views) =>
      YtUtils.formatCompactViews(views);

  bool matchesExplicitRequirement(String videoTitle, bool targetExplicit) =>
      YtUtils.matchesExplicitRequirement(videoTitle, targetExplicit);

  dynamic findDeepKey(dynamic obj, String targetKey) =>
      YtUtils.findDeepKey(obj, targetKey);

  void clearCache() {
    _innertubeService.clearCache();
    _streamResolver.clearCache();
    _searchService.clearCache();
  }

  void dispose() {
    _client.close();
    _browserClient.close();
  }

  // --- YouTube Music InnerTube Delegations ---

  Future<({List<Album> releases, List<Album> playlists})> getArtistReleasesAndPlaylists(
    String artistName, {
    String artistId = '',
    int limit = 60,
  }) async {
    final cacheKey = 'youtube:discography:$artistId:$artistName';
    final cached = await DatabaseService.instance.readSearchCache(cacheKey);
    if (cached != null) {
      final payload = jsonDecode(cached) as Map<String, dynamic>;
      return (
        releases: (payload['releases'] as List<dynamic>? ?? [])
            .map((item) => Album.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(),
        playlists: (payload['playlists'] as List<dynamic>? ?? [])
            .map((item) => Album.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(),
      );
    }

    final result = await _innertubeService.getArtistReleasesAndPlaylists(
      artistName,
      artistId: artistId,
      limit: limit,
    );
    unawaited(DatabaseService.instance.writeSearchCache(
      cacheKey: cacheKey,
      cacheType: 'youtube_discography',
      queryText: artistName,
      payload: jsonEncode({
        'artistId': artistId,
        'artistName': artistName,
        'releases': result.releases.map((item) => item.toJson()).toList(),
        'playlists': result.playlists.map((item) => item.toJson()).toList(),
      }),
      ttl: const Duration(minutes: 15),
    ));
    return result;
  }

  Future<({String title, String logoUrl, String bannerUrl})?> getChannelDetails(String channelId) =>
      _innertubeService.getChannelDetails(channelId);

  Future<({String title, String logoUrl, String bannerUrl})?> getArtistChannelDetails(
    String artistName, {
    String artistId = '',
  }) =>
      _innertubeService.getArtistChannelDetails(artistName, artistId: artistId);

  // --- Search Delegations ---

  Future<List<Track>> searchOnlineTracks(String query, {int limit = 3}) =>
      _searchService.searchOnlineTracks(query, limit: limit);

  Future<List<Album>> searchPlaylists(String query, {int limit = 25}) =>
      _searchService.searchPlaylists(query, limit: limit);

  Future<SearchEngineResponse> searchCatalog(String query) =>
      _searchService.searchCatalog(query);

  Future<({String? albumName, List<Track> tracks})> fetchAlbumDetailsAndTracks(Track track) =>
      _searchService.fetchAlbumDetailsAndTracks(track);

  Future<({Track? matchedTrack, Album? matchedAlbum, Track? matchedPlaylistTrack, Album? matchedPlaylist, List<Album> allReleases, List<Album> allPlaylists})> findMatchingReleaseTrack(
    Track firstTrack, {
    String cleanQuery = '',
    String artistId = '',
  }) =>
      _searchService.findMatchingReleaseTrack(firstTrack, cleanQuery: cleanQuery, artistId: artistId);

  // --- Stream Resolution & Download Delegations ---

  Future<String?> resolveVideoId(Track track) =>
      _streamResolver.resolveVideoId(track);

  Future<StreamInfo?> getAudioStreamInfo(String videoId) =>
      _streamResolver.getAudioStreamInfo(videoId);

  Future<String?> getAudioStreamUrl(String videoId) =>
      _streamResolver.getAudioStreamUrl(videoId);

  Future<AudioSource?> resolveAudioSource(
    Track track, {
    dynamic tag,
    void Function(int bitrate)? onBitrateResolved,
  }) =>
      _streamResolver.resolveAudioSource(
        track,
        tag: tag,
        onBitrateResolved: onBitrateResolved,
      );

  Future<String> resolvePlayableAudioUrl(Track track) =>
      _streamResolver.resolvePlayableAudioUrl(track);

  Future<String?> downloadAudioStream(
    Track track, {
    String? directStreamUrl,
    void Function(double progress)? onProgress,
    void Function(int bitrate)? onBitrateResolved,
  }) =>
      _streamResolver.downloadAudioStream(
        track,
        directStreamUrl: directStreamUrl,
        onProgress: onProgress,
        onBitrateResolved: onBitrateResolved,
      );
}
