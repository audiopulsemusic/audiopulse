import 'dart:async';
import 'package:http/http.dart' as http;
import '../models/track.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/playlist.dart';
import '../models/api_config.dart';
import '../data/mock_data.dart';
import 'network/network_exception.dart';
import 'network/network_guard.dart';
import 'network/url_security_policy.dart';

class ApiService {
  final ApiConfig _config = ApiConfig();
  final http.Client _client;
  NetworkException? _lastError;

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  ApiConfig get config => _config;
  NetworkException? get lastError => _lastError;

  void updateConfig({String? baseUrl, String? mode, String? apiKey, String? status}) {
    final normalized = baseUrl == null ? null : UrlSecurityPolicy.normalizeApiBase(baseUrl);
    if (normalized != null) _config.baseUrl = normalized.toString();
    if (mode != null) _config.mode = mode;
    if (apiKey != null) _config.apiKey = apiKey;
    if (status != null) _config.status = status;
  }

  Future<bool> checkBackendHealth(String url) async {
    final base = UrlSecurityPolicy.normalizeApiBase(url);
    if (base == null) {
      _lastError = const SecurityValidationException('Backend non autorisé.');
      _setMockMode();
      return false;
    }
    try {
      _config.status = 'connecting';
      final response = await NetworkGuard.getWithRedirects(
        client: _client,
        uri: UrlSecurityPolicy.appendPath(base, 'health'),
        timeout: const Duration(seconds: 3),
        validate: (destination) => _validateApiDestination(destination, base),
      );
      await response.stream.drain<void>();
      if (response.statusCode == 200) {
        _config.baseUrl = base.toString();
        _config.isConnected = true;
        _config.mode = 'live';
        _config.status = 'online';
        _lastError = null;
        return true;
      }
      _lastError = InvalidResponseException.status(response.statusCode);
    } on TimeoutException {
      _lastError = const NetworkTimeoutException();
    } on NetworkException catch (error) {
      _lastError = error;
    } catch (error) {
      _lastError = NetworkUnavailableException(error.toString());
    }
    _setMockMode();
    return false;
  }

  void _setMockMode() {
    _config.status = 'mock_active';
    _config.mode = 'mock';
    _config.isConnected = false;
  }

  Future<void> _validateApiDestination(Uri destination, Uri base) async {
    if (destination.userInfo.isNotEmpty ||
        destination.scheme != base.scheme ||
        destination.host.toLowerCase() != base.host.toLowerCase() ||
        destination.port != base.port) {
      throw const SecurityValidationException('Redirection backend hors allowlist.');
    }
  }

  Future<http.Response> _getJson(Uri base, Uri uri) async {
    final streamed = await NetworkGuard.getWithRedirects(
      client: _client,
      uri: uri,
      validate: (destination) => _validateApiDestination(destination, base),
    );
    NetworkGuard.ensureSuccess(streamed);
    if (!NetworkGuard.isJsonContentType(streamed.headers['content-type'])) {
      await streamed.stream.drain<void>();
      throw const InvalidResponseException('Content-Type JSON attendu.');
    }
    final bytes = await NetworkGuard.readLimited(streamed, maxBytes: 2 * 1024 * 1024);
    return http.Response.bytes(bytes, streamed.statusCode, headers: streamed.headers);
  }

  Future<List<Track>> getTracks() async {
    if (_config.mode == 'live' && _config.isConnected) {
      try {
        final base = UrlSecurityPolicy.normalizeApiBase(_config.baseUrl);
        if (base == null) throw const SecurityValidationException();
        final res = await _getJson(base, UrlSecurityPolicy.appendPath(base, 'tracks'));
        final List<dynamic> data = NetworkGuard.decodeJsonList(res);
        return data.map((json) => Track.fromJson(json as Map<String, dynamic>)).toList();
      } on TimeoutException {
        throw const NetworkTimeoutException();
      } on NetworkException {
        rethrow;
      } catch (e) {
        throw NetworkUnavailableException(e.toString());
      }
    }
    return List<Track>.unmodifiable(mockTracks);
  }

  Future<Map<String, dynamic>> search(String query) async {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) {
      return {
        'tracks': <Track>[],
        'artists': <Artist>[],
        'albums': <Album>[],
        'playlists': <Playlist>[],
      };
    }

    if (_config.mode == 'live' && _config.isConnected) {
      try {
        final base = UrlSecurityPolicy.normalizeApiBase(_config.baseUrl);
        if (base == null) throw const SecurityValidationException();
        final res = await _getJson(
          base,
          UrlSecurityPolicy.appendPath(base, 'search', queryParameters: {'q': query}),
        );
        final data = NetworkGuard.decodeJsonObject(res);
        return {
          'tracks': (data['tracks'] as List<dynamic>?)
              ?.map((e) => Track.fromJson(e as Map<String, dynamic>))
              .toList() ??
              [],
          'artists': (data['artists'] as List<dynamic>?)
              ?.map((e) => Artist.fromJson(e as Map<String, dynamic>))
              .toList() ??
              [],
          'albums': (data['albums'] as List<dynamic>?)
              ?.map((e) => Album.fromJson(e as Map<String, dynamic>))
              .toList() ??
              [],
          'playlists': (data['playlists'] as List<dynamic>?)
              ?.map((e) => Playlist.fromJson(e as Map<String, dynamic>))
              .toList() ??
              [],
        };
      } on TimeoutException {
        throw const NetworkTimeoutException();
      } on NetworkException {
        rethrow;
      } catch (e) {
        throw NetworkUnavailableException(e.toString());
      }
    }

    final filteredTracks = mockTracks.where((t) {
      return t.title.toLowerCase().contains(q) ||
          t.artist.toLowerCase().contains(q) ||
          t.genre.toLowerCase().contains(q);
    }).toList();

    final filteredArtists = mockArtists.where((a) {
      return a.name.toLowerCase().contains(q) || a.bio.toLowerCase().contains(q);
    }).toList();

    final filteredAlbums = mockAlbums.where((al) {
      return al.title.toLowerCase().contains(q) ||
          al.artist.toLowerCase().contains(q);
    }).toList();

    final filteredPlaylists = mockPlaylists.where((p) {
      return p.title.toLowerCase().contains(q) ||
          p.description.toLowerCase().contains(q);
    }).toList();

    return {
      'tracks': filteredTracks,
      'artists': filteredArtists,
      'albums': filteredAlbums,
      'playlists': filteredPlaylists,
    };
  }

  @Deprecated('Use DownloadController/DatabaseService; ApiService is transport-only.')
  Future<bool> toggleDownloadTrack(String trackId) async => false;

  @Deprecated('Use LibraryController/DatabaseService; ApiService is transport-only.')
  Future<Playlist> createPlaylist(String title, String description) {
    throw UnsupportedError('ApiService no longer owns playlists.');
  }

  @Deprecated('Use LibraryController/DatabaseService; ApiService is transport-only.')
  Future<bool> addTrackToPlaylist(String playlistId, Track track) async => false;
}

final ApiService apiService = ApiService();
