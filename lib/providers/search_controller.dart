import 'package:flutter/foundation.dart';

import '../models/search_engine_response.dart';
import '../models/album.dart';
import '../models/track.dart';
import '../services/fetch/yt_search_service.dart';

enum SearchStatus { idle, loading, success, empty, error }

class SearchController extends ChangeNotifier {
  SearchController({
    YtSearchService? service,
    Future<SearchEngineResponse> Function(String query)? searchOperation,
  })  : _service = service ?? YtSearchService(),
        _searchOperation = searchOperation;

  final YtSearchService _service;
  final Future<SearchEngineResponse> Function(String query)? _searchOperation;
  SearchEngineResponse _results = SearchEngineResponse.empty();
  SearchStatus _status = SearchStatus.idle;
  Object? _error;
  String _query = '';
  Track? _selectedArtistTrack;
  List<Album> _artistReleases = const [];
  List<Album> _artistPlaylists = const [];
  String _artistAvatarUrl = '';
  Album? _matchedAlbum;
  int _generation = 0;

  SearchEngineResponse get results => _results;
  SearchStatus get status => _status;
  Object? get error => _error;
  String get query => _query;
  Track? get selectedArtistTrack => _selectedArtistTrack;
  List<Album> get artistReleases => List.unmodifiable(_artistReleases);
  List<Album> get artistPlaylists => List.unmodifiable(_artistPlaylists);
  String get artistAvatarUrl => _artistAvatarUrl;
  Album? get matchedAlbum => _matchedAlbum;

  void setArtistContext({
    required Track track,
    required List<Album> releases,
    required List<Album> playlists,
    required String avatarUrl,
    Album? matchedAlbum,
  }) {
    _selectedArtistTrack = track;
    _artistReleases = List.unmodifiable(releases);
    _artistPlaylists = List.unmodifiable(playlists);
    _artistAvatarUrl = avatarUrl;
    _matchedAlbum = matchedAlbum;
    notifyListeners();
  }

  Future<void> search(String query) async {
    final generation = ++_generation;
    _query = query;
    if (query.trim().isEmpty) {
      _results = SearchEngineResponse.empty();
      _status = SearchStatus.idle;
      _error = null;
      notifyListeners();
      return;
    }
    _status = SearchStatus.loading;
    _error = null;
    notifyListeners();
    try {
      final result = await (_searchOperation ?? ((q) => _service.searchCatalog(q)))(query);
      if (generation != _generation) return;
      _results = result;
      _status = result.isEmpty ? SearchStatus.empty : SearchStatus.success;
    } catch (error) {
      if (generation != _generation) return;
      _error = error;
      _status = SearchStatus.error;
    }
    notifyListeners();
  }

  void clear() {
    _generation++;
    _query = '';
    _selectedArtistTrack = null;
    _artistReleases = const [];
    _artistPlaylists = const [];
    _artistAvatarUrl = '';
    _results = SearchEngineResponse.empty();
    _status = SearchStatus.idle;
    _error = null;
    notifyListeners();
  }
}
