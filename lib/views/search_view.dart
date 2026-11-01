import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';
import '../providers/search_controller.dart';
import '../models/track.dart';
import '../models/album.dart';
import '../models/search_engine_response.dart';
import '../services/audio_fetch_service.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_network_image.dart';
import '../widgets/album_playlist_stage.dart';
import 'search/search_skeletons.dart';
import 'search/artist_group_widgets.dart';
import '../widgets/track_tile.dart';

class SearchView extends StatefulWidget {
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final _searchController = TextEditingController();
  List<Track> _onlineResults = [];
  SearchEngineResponse? _searchResults;
  bool _isSearchingOnline = false;
  int _searchGeneration = 0; // MED-10: monotonic token to drop stale async responses

  List<String> _recentSearches = [];
  AudioProvider? _audioProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final audio = context.read<AudioProvider>();
    if (_audioProvider != audio) {
      _audioProvider?.pendingSearchQuery.removeListener(_onPendingSearchQuery);
      _audioProvider = audio;
      _audioProvider?.pendingSearchQuery.addListener(_onPendingSearchQuery);
    }
  }

  void _onPendingSearchQuery() {
    if (!mounted) return;
    final audio = _audioProvider;
    if (audio == null) return;
    final pending = audio.pendingSearchQuery.value;
    if (pending != null && pending.trim().isNotEmpty) {
      audio.pendingSearchQuery.value = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _selectSuggestion(pending.trim());
      });
    }
  }

  Future<void> _loadSearchHistory() async {
    try {
      final history = await DatabaseService.instance.getSearchHistory(limit: 8);
      if (mounted) {
        setState(() {
          _recentSearches = history;
        });
      }
    } catch (_) {}
  }

  Future<void> _removeSearchHistory(String query) async {
    try {
      await DatabaseService.instance.removeSearchHistory(query);
      await _loadSearchHistory();
    } catch (_) {}
  }

  Future<void> _clearSearchHistory() async {
    try {
      await DatabaseService.instance.clearSearchHistory();
      if (mounted) {
        setState(() {
          _recentSearches = [];
        });
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _loadSearchHistory();
    DatabaseService.instance.searchHistoryGeneration.addListener(_loadSearchHistory);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final audio = context.read<AudioProvider>();
      final pending = audio.pendingSearchQuery.value;
      if (pending != null && pending.trim().isNotEmpty) {
        audio.pendingSearchQuery.value = null;
        _selectSuggestion(pending.trim());
        return;
      }
      final persisted = audio.searchController;
      if (persisted.query.isEmpty || persisted.results.isEmpty) return;
      final Map<String, Track> uniqueMap = {};
      for (final track in persisted.results.tracks) {
        final key = track.artist.trim().toLowerCase();
        if (key.isNotEmpty && !uniqueMap.containsKey(key)) {
          uniqueMap[key] = track;
        }
      }
      final candidates = uniqueMap.values.toList();
      final targetedArtist = persisted.selectedArtistTrack?.artist.trim().toLowerCase() ?? '';
      final artistTracks = persisted.results.tracks.where(
        (t) => targetedArtist.isNotEmpty && (
               t.artist.trim().toLowerCase() == targetedArtist ||
               targetedArtist.contains(t.artist.toLowerCase()) ||
               t.artist.toLowerCase().contains(targetedArtist))
      ).take(3).toList();
      final displayed = artistTracks.length >= 3
          ? artistTracks
          : [...artistTracks, ...persisted.results.tracks.where((t) => !artistTracks.contains(t)).take(3 - artistTracks.length)];

      final top2Tracks = persisted.results.tracks.take(2).toList();
      final hasMultipleArtistsInTop2 = top2Tracks.length >= 2 &&
          top2Tracks[0].artist.trim().toLowerCase() != top2Tracks[1].artist.trim().toLowerCase();

      setState(() {
        _searchController.text = persisted.query;
        _searchController.selection = TextSelection.fromPosition(
          TextPosition(offset: persisted.query.length),
        );
        _searchResults = persisted.results;
        _onlineResults = displayed.isNotEmpty ? displayed : persisted.results.tracks.take(3).toList();
        _uniqueCandidateArtists = candidates;
        _showArtistSelector = hasMultipleArtistsInTop2 && candidates.length > 1;
        _isSearchingOnline = persisted.status == SearchStatus.loading;
        _targetedTrack = persisted.selectedArtistTrack;
        _artistReleases = persisted.artistReleases;
        _artistPlaylists = persisted.artistPlaylists;
        _artistAvatarUrl = persisted.artistAvatarUrl;
        _matchedReleaseAlbum = persisted.matchedAlbum;
        _matchedPlaylist = _artistPlaylists.firstOrNull;
      });
    });
  }

  @override
  void dispose() {
    DatabaseService.instance.searchHistoryGeneration.removeListener(_loadSearchHistory);
    _audioProvider?.pendingSearchQuery.removeListener(_onPendingSearchQuery);
    _searchController.dispose();
    super.dispose();
  }

  // Purely updates the clear button state on typing.
  // Search is strictly launched only upon keyboard submission (Enter key).
  void _onQueryChanged(String query) {
    final rawQuery = query.trim();

    if (rawQuery.isEmpty) {
      setState(() {
        _onlineResults = [];
        _searchResults = null;
        _isSearchingOnline = false;
        _uniqueCandidateArtists = [];
        _showArtistSelector = false;
        _artistAvatarUrl = '';
        _matchedReleaseAlbum = null;
        _matchedPlaylist = null;
        _artistReleases = [];
        _artistPlaylists = [];
        _targetedTrack = null;
      });
      _loadSearchHistory();
      return;
    }

    setState(() {});
  }

  void _selectSuggestion(String suggestion) {
    _searchController.text = suggestion;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: suggestion.length),
    );
    _performSearch(suggestion, unfocus: true);
  }

  Album? _matchedReleaseAlbum;
  Album? _matchedPlaylist;
  String _artistAvatarUrl = '';
  List<Track> _uniqueCandidateArtists = [];
  Track? _targetedTrack;
  bool _showArtistSelector = false;
  bool _isResolvingTarget = false;
  bool _isResolvingAlbums = false;
  List<Album> _artistReleases = [];
  List<Album> _artistPlaylists = [];

  Future<void> _targetArtist(Track track, {SearchEngineResponse? allResults, List<Track>? localResults, int? generation}) async {
    if (generation != null && generation != _searchGeneration) return;

    final searchRes = allResults ?? _searchResults;
    final allTracks = localResults ?? searchRes?.tracks ?? _onlineResults;
    final targetedArtistName = track.artist.trim().toLowerCase();

    // 1. Filter up to 3 tracks for this specific targeted artist, excluding youtube tracks which have their own card
    final mainTracks = allTracks.where((t) => t.source != 'youtube').toList();
    final artistTracks = mainTracks.where(
      (t) => t.artist.trim().toLowerCase() == targetedArtistName ||
             (track.artistId.isNotEmpty && t.artistId == track.artistId) ||
             t.artist.toLowerCase().contains(targetedArtistName) ||
             targetedArtistName.contains(t.artist.toLowerCase())
    ).take(3).toList();

    final List<Track> displayedTracks;
    if (artistTracks.length >= 3 || localResults != null) {
      displayedTracks = artistTracks.isNotEmpty ? artistTracks : mainTracks.take(3).toList();
    } else {
      final remaining = mainTracks.where((t) => !artistTracks.contains(t)).take(3 - artistTracks.length);
      displayedTracks = [...artistTracks, ...remaining];
    }

    // Direct album from track metadata (no heavy discography fetch during track search)
    Album? directAlbum;
    if (track.album.isNotEmpty &&
        track.album != 'Single' &&
        track.album != 'Single Web' &&
        track.album != 'Streaming Web' &&
        track.album != 'Master Hi-Fi • 320k eq') {
      directAlbum = Album(
        id: track.albumId.isNotEmpty ? track.albumId : 'album_${track.id}',
        title: track.album,
        artist: track.artist,
        artistId: track.artistId,
        coverUrl: track.coverUrl,
        releaseYear: track.releaseYear > 0 ? track.releaseYear : DateTime.now().year,
        tracksCount: 1,
        genre: track.genre.isNotEmpty ? track.genre : 'Album',
        ambientColor: track.ambientColor,
      );
      unawaited(DatabaseService.instance.saveAlbumsIndex([directAlbum]));
    }

    // Check if artist avatar is already present in search results
    String initialAvatar = '';
    if (searchRes != null) {
      final matchingArtist = searchRes.artists.where((a) =>
        a.name.toLowerCase() == track.artist.toLowerCase() ||
        (track.artistId.isNotEmpty && a.id == track.artistId)
      ).firstOrNull;
      if (matchingArtist != null && matchingArtist.avatarUrl.isNotEmpty) {
        initialAvatar = matchingArtist.avatarUrl;
      }
    }

    if (mounted && (generation == null || generation == _searchGeneration)) {
      setState(() {
        _targetedTrack = track;
        _onlineResults = displayedTracks;
        _isResolvingTarget = initialAvatar.isEmpty;
        _isResolvingAlbums = false; // Fast! No heavy discography resolution during track search
        _artistAvatarUrl = initialAvatar;
        _matchedReleaseAlbum = directAlbum;
        _matchedPlaylist = null;
        _artistReleases = directAlbum != null ? [directAlbum] : [];
        _artistPlaylists = [];
      });
      context.read<AudioProvider>().searchController.setArtistContext(
        track: track,
        releases: _artistReleases,
        playlists: const [],
        avatarUrl: _artistAvatarUrl,
        matchedAlbum: _matchedReleaseAlbum,
      );
    }

    // Résoudre en tâche de fond le débit réel du morceau ciblé s'il est inconnu
    if (track.bitrate == 0) {
      unawaited(() async {
        try {
          final videoId = await AudioFetchService.instance.streamResolver.resolveVideoId(track);
          if (videoId != null && videoId.isNotEmpty) {
            final info = await AudioFetchService.instance.streamResolver.getAudioStreamInfo(videoId);
            if (info != null) {
              final kbps = info.bitrate.kiloBitsPerSecond.round();
              if (kbps > 0) {
                await DatabaseService.instance.updateTrackBitrate(track.id, kbps);
                if (mounted && (generation == null || generation == _searchGeneration)) {
                  setState(() {
                    _onlineResults = _onlineResults.map((t) => t.id == track.id ? t.copyWith(bitrate: kbps) : t).toList();
                    if (_targetedTrack?.id == track.id) {
                      _targetedTrack = _targetedTrack!.copyWith(bitrate: kbps);
                    }
                  });
                }
              }
            }
          }
        } catch (_) {}
      }());
    }

    // Resolve & persist artist avatar immediately in SQLite
    try {
      if (initialAvatar.isNotEmpty) {
        unawaited(DatabaseService.instance.saveArtistIndex(
          track.artist,
          artistId: track.artistId,
          avatarUrl: initialAvatar,
        ));
      } else {
        final cached = await DatabaseService.instance.findArtistByName(track.artist);
        if (cached != null && cached.avatarUrl.isNotEmpty) {
          if (mounted && (generation == null || generation == _searchGeneration)) {
            setState(() {
              _artistAvatarUrl = cached.avatarUrl;
              _isResolvingTarget = false;
            });
            context.read<AudioProvider>().searchController.setArtistContext(
              track: track,
              releases: _artistReleases,
              playlists: const [],
              avatarUrl: _artistAvatarUrl,
              matchedAlbum: _matchedReleaseAlbum,
            );
          }
          return;
        }

        final details = await AudioFetchService.instance.getArtistChannelDetails(
          track.artist,
          artistId: track.artistId,
        );
        if (details != null && details.logoUrl.isNotEmpty) {
          if (mounted && (generation == null || generation == _searchGeneration)) {
            setState(() {
              _artistAvatarUrl = details.logoUrl;
              _isResolvingTarget = false;
            });
            context.read<AudioProvider>().searchController.setArtistContext(
              track: track,
              releases: _artistReleases,
              playlists: const [],
              avatarUrl: _artistAvatarUrl,
              matchedAlbum: _matchedReleaseAlbum,
            );
          }
          await DatabaseService.instance.saveArtistIndex(
            track.artist,
            artistId: track.artistId,
            avatarUrl: details.logoUrl,
          );
        } else {
          if (mounted && (generation == null || generation == _searchGeneration)) {
            setState(() {
              _isResolvingTarget = false;
            });
          }
        }
      }
    } catch (_) {
      if (mounted && (generation == null || generation == _searchGeneration)) {
        setState(() {
          _isResolvingTarget = false;
        });
      }
    }
  }

  Future<void> _performSearch(String query, {bool unfocus = false}) async {
    final rawQuery = query.trim();
    if (rawQuery.isEmpty) return;
    final searchGen = ++_searchGeneration;

    if (unfocus) {
      FocusScope.of(context).unfocus();
    }

    if (!mounted || searchGen != _searchGeneration) return;

    // 1. Sauvegarder dans l'historique de recherche SQLite
    unawaited(DatabaseService.instance.addSearchHistory(rawQuery).then((_) => _loadSearchHistory()));

    // 2. Recherche locale instantanée (0 ms, Offline-First)
    final localMatches = await DatabaseService.instance.searchLocalTracks(rawQuery, limit: 5);
    if (!mounted || searchGen != _searchGeneration) return;

    setState(() {
      _isSearchingOnline = true;
      _isResolvingTarget = localMatches.isEmpty;
      _isResolvingAlbums = false;
      _artistAvatarUrl = '';
      _targetedTrack = null;
      _onlineResults = localMatches.take(3).toList();
      _matchedReleaseAlbum = null;
      _matchedPlaylist = null;
      _artistReleases = [];
      _artistPlaylists = [];
    });

    if (localMatches.isNotEmpty) {
      _targetArtist(localMatches.first, localResults: localMatches, generation: searchGen);
    }

    try {
      // ⚡ Étape 3 : Morceaux en ligne (1 InnerTube + 2 YouTube)
      final results = await context.read<AudioProvider>().searchCatalogOnline(rawQuery);
      if (!mounted || searchGen != _searchGeneration) return;

      // Fusion intelligente sans doublons : en ligne en priorité, complété par local
      final List<Track> combinedTracks = List.from(results.tracks);
      final Set<String> seenIds = combinedTracks.map((t) => t.id).toSet();
      for (final lt in localMatches) {
        if (!seenIds.contains(lt.id) && combinedTracks.length < 5) {
          seenIds.add(lt.id);
          combinedTracks.add(lt);
        }
      }

      final mergedResults = SearchEngineResponse(
        bestMatch: results.bestMatch,
        artists: results.artists,
        albums: results.albums,
        playlists: results.playlists,
        tracks: combinedTracks,
      );

      // Déduplication par artiste unique parmi tous les résultats
      final Map<String, Track> uniqueMap = {};
      for (final track in mergedResults.tracks) {
        final key = track.artist.trim().toLowerCase();
        if (key.isNotEmpty && !uniqueMap.containsKey(key)) {
          uniqueMap[key] = track;
        }
      }
      final uniqueList = uniqueMap.values.toList();
      final top2 = mergedResults.tracks.take(2).toList();
      final hasMultipleArtistsInTop2 = top2.length >= 2 &&
          top2[0].artist.trim().toLowerCase() != top2[1].artist.trim().toLowerCase();

      if (mounted && searchGen == _searchGeneration) {
        setState(() {
          _searchResults = mergedResults;
          _isSearchingOnline = false;
          _uniqueCandidateArtists = uniqueList;
          _showArtistSelector = hasMultipleArtistsInTop2 && uniqueList.length > 1;
        });
      }

      if (uniqueList.isNotEmpty) {
        // Étapes 2 & 3 lancées pour l'artiste principal
        _targetArtist(uniqueList.first, allResults: mergedResults, generation: searchGen);
      } else {
        if (mounted && searchGen == _searchGeneration) {
          setState(() {
            _onlineResults = [];
            _matchedReleaseAlbum = null;
            _matchedPlaylist = null;
            _artistAvatarUrl = '';
            _showArtistSelector = false;
            _isResolvingTarget = false;
            _isResolvingAlbums = false;
          });
        }
      }
    } catch (e) {
      if (mounted && searchGen == _searchGeneration) {
        setState(() {
          _isSearchingOnline = false;
          _isResolvingTarget = false;
          _isResolvingAlbums = false;
        });
      }
    }
  }

  // Explicit search triggered by Enter key on keyboard
  Future<void> _submitSearch([String? customQuery]) async {
    if (customQuery != null) {
      _selectSuggestion(customQuery);
    } else {
      _performSearch(_searchController.text, unfocus: true);
    }
  }

  void _showAlbumTracksBottomSheet(BuildContext context, Album album) {
    // Identifier le vrai morceau associé pour déclencher la même résolution que le plein écran
    final matchTrack = _targetedTrack ??
        _onlineResults.where((t) =>
            t.album.toLowerCase() == album.title.toLowerCase() ||
            t.artist.toLowerCase() == album.artist.toLowerCase()
        ).firstOrNull ??
        Track(
          id: album.id.startsWith('album_') ? album.id.replaceFirst('album_', '') : album.id,
          title: album.title,
          artist: album.artist,
          album: album.title,
          duration: 180,
          coverUrl: album.coverUrl,
          audioUrl: 'yt://${album.id}',
          genre: album.genre.isNotEmpty ? album.genre : 'Album',
          ambientColor: album.ambientColor,
        );

    // Utilise exactement le même composant et le même code que le plein écran
    AlbumPlaylistStage.showAsBottomSheet(
      context,
      matchTrack: matchTrack,
      title: album.title,
      artist: album.artist,
      coverUrl: album.coverUrl,
      genre: album.genre,
      ambientColor: AppTheme.parseHexColor(album.ambientColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 14, bottom: 150),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0x3306B6D4),
                  Color(0x1F3B82F6),
                  Color(0x150A0D14),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0x3306B6D4)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1106B6D4),
                  blurRadius: 20,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0x3306B6D4),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0x4D06B6D4)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.search, size: 11, color: Color(0xFF22D3EE)),
                            SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                'MOTEUR DE RECHERCHE UNIFIÉ',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF22D3EE),
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'En ligne & Stream',
                      style: TextStyle(fontSize: 10, color: AppTheme.textSecondary, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'Recherche Musicale',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Explorez des millions de morceaux, discographies complètes et artistes.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Search Input Bar (Validation via Clavier)
          Container(
            decoration: BoxDecoration(
              color: const Color(0xCC0E121B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x33FFFFFF)),
            ),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 14),
                  child: Icon(LucideIcons.search, color: AppTheme.primaryPink, size: 20),
                ),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onQueryChanged,
                    onSubmitted: (q) => _submitSearch(q),
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Titre, artiste (Appuyez sur Entrée)...',
                      hintStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      suffixIcon: _isSearchingOnline
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.primaryPink,
                                ),
                              ),
                            )
                          : (_searchController.text.isNotEmpty
                              ? IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _onlineResults = [];
                                      _searchResults = null;
                                      _isSearchingOnline = false;
                                      _artistAvatarUrl = '';
                                      _targetedTrack = null;
                                      _matchedReleaseAlbum = null;
                                      _matchedPlaylist = null;
                                      _artistReleases = [];
                                      _artistPlaylists = [];
                                      _uniqueCandidateArtists = [];
                                      _showArtistSelector = false;
                                    });
                                  },
                                  icon: const Icon(LucideIcons.x, size: 16, color: AppTheme.textMuted),
                                )
                              : null),
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          if (_isSearchingOnline && _onlineResults.isEmpty)
            _buildSkeletonSearchResults()
          else if (_onlineResults.isEmpty && _searchController.text.trim().isEmpty) ...[
            if (_recentSearches.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'RECHERCHES RÉCENTES',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMuted,
                      letterSpacing: 1.1,
                    ),
                  ),
                  InkWell(
                    onTap: _clearSearchHistory,
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text(
                        'Tout effacer',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.primaryPink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _recentSearches.map((query) {
                  return Container(
                    decoration: BoxDecoration(
                      color: const Color(0x14FFFFFF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x1FFFFFFF)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () => _submitSearch(query),
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(LucideIcons.clock, size: 12, color: AppTheme.primaryPink),
                                const SizedBox(width: 6),
                                Text(
                                  query,
                                  style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => _removeSearchHistory(query),
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                          child: const Padding(
                            padding: EdgeInsets.fromLTRB(4, 7, 8, 7),
                            child: Icon(LucideIcons.x, size: 12, color: AppTheme.textMuted),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ] else ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Icon(LucideIcons.search, size: 40, color: Color(0x33FFFFFF)),
                      SizedBox(height: 12),
                      Text(
                        'Recherchez un morceau, un artiste ou un album',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Validez avec la touche Entrée de votre clavier',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ] else if (_onlineResults.isEmpty && (_searchResults == null || _searchResults!.tracks.where((t) => t.source == 'youtube').isEmpty))
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    const Icon(LucideIcons.search_x, size: 36, color: AppTheme.textMuted),
                    const SizedBox(height: 10),
                    const Text(
                      'Appuyez sur la touche Rechercher de votre clavier',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Recherche pour "${_searchController.text.trim()}"',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // Candidate artists selector (affiché uniquement en cas d'artistes concurrents dans le top 2)
            _buildCandidateArtistSelector(),

            // Tracks list grouped by targeted artist (⚡ Morceaux affichés immédiatement, discographie résolue en arrière-plan)
            if (_onlineResults.isNotEmpty)
              _buildGroupedTracksList(
                _onlineResults,
                searchQuery: _searchController.text.trim(),
                matchedAlbum: _matchedReleaseAlbum,
                matchedPlaylist: _matchedPlaylist,
                artistAvatarUrl: _artistAvatarUrl,
                artistReleases: _artistReleases,
                artistPlaylists: _artistPlaylists,
                isResolvingTarget: _isResolvingTarget,
                isResolvingAlbums: _isResolvingAlbums,
              ),

            // Youtube Results Card
            if (_searchResults != null && _searchResults!.tracks.where((t) => t.source == 'youtube').isNotEmpty)
              _buildYoutubeResultsCard(
                _searchResults!.tracks.where((t) => t.source == 'youtube').take(5).toList(),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildCandidateArtistSelector() {
    if (!_showArtistSelector || _uniqueCandidateArtists.length <= 1) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CHOISIR UN ARTISTE / CHAÎNE',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AppTheme.primaryPink,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 68,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _uniqueCandidateArtists.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, idx) {
              final track = _uniqueCandidateArtists[idx];
              final isSelected = _targetedTrack?.artist.trim().toLowerCase() == track.artist.trim().toLowerCase();

              return InkWell(
                onTap: () => _targetArtist(track, generation: _searchGeneration),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 220,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0x28EC4899) : const Color(0xFF131826),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? AppTheme.primaryPink : Colors.white.withValues(alpha: 0.08),
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      AppNetworkImage(
                        imageUrl: track.coverUrl,
                        width: 44,
                        height: 44,
                        borderRadius: 10,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.white : AppTheme.textMuted,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: isSelected ? AppTheme.primaryPink : Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(LucideIcons.badge_check, size: 16, color: AppTheme.primaryPink),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _buildSkeletonSearchResults() {
    return SearchSkeletons.buildSkeletonSearchResults();
  }

  Widget _buildGroupedTracksList(
    List<Track> tracks, {
    String searchQuery = '',
    Album? matchedAlbum,
    Album? matchedPlaylist,
    String artistAvatarUrl = '',
    List<Album> artistReleases = const [],
    List<Album> artistPlaylists = const [],
    bool isResolvingTarget = false,
    bool isResolvingAlbums = false,
    bool initialShowPlaylists = false,
  }) {
    final Map<String, ({String artistName, String artistId, List<Track> tracks})> grouped = {};
    for (final track in tracks) {
      final rawArtist = track.artist.trim().isNotEmpty ? track.artist.trim() : 'Artiste Inconnu';
      final groupKey = track.artistId.trim().isNotEmpty
          ? track.artistId.trim()
          : rawArtist.toLowerCase();

      if (!grouped.containsKey(groupKey)) {
        grouped[groupKey] = (
          artistName: rawArtist,
          artistId: track.artistId.trim(),
          tracks: [track],
        );
      } else {
        grouped[groupKey]!.tracks.add(track);
      }
    }

    final displayGroups = grouped.values.take(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: displayGroups.map((group) {
        return ArtistGroupBlock(
          artistName: group.artistName,
          artistId: group.artistId,
          tracks: group.tracks,
          searchQuery: searchQuery,
          matchedAlbum: matchedAlbum,
          matchedPlaylist: matchedPlaylist,
          artistAvatarUrl: artistAvatarUrl,
          artistReleases: artistReleases,
          artistPlaylists: artistPlaylists,
          isResolvingTarget: isResolvingTarget,
          isResolvingAlbums: isResolvingAlbums,
          initialShowPlaylists: initialShowPlaylists,
          onAlbumTap: (album) => _showAlbumTracksBottomSheet(context, album),
        );
      }).toList(),
    );
  }

  Widget _buildYoutubeResultsCard(List<Track> ytTracks) {
    if (ytTracks.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131826),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF0000),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(LucideIcons.play, size: 10, color: Colors.white),
              ),
              const SizedBox(width: 8),
              const Text(
                'RÉSULTATS YOUTUBE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: ytTracks.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, idx) {
              final track = ytTracks[idx];
              return TrackTile(
                track: track,
                playlistContext: ytTracks,
                showQualityBadge: false,
                showDownloadButton: true,
              );
            },
          ),
        ],
      ),
    );
  }
}
