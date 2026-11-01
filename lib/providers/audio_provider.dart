import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/playlist.dart';
import '../models/user_profile.dart';
import '../data/mock_data.dart';
import '../services/audio_handler.dart';
import '../services/audio_player_service.dart';
import '../services/database_service.dart';
import '../services/audio_fetch_service.dart';
import '../models/search_engine_response.dart';
import '../models/app_view.dart';
import 'library_controller.dart';
import 'download_controller.dart';
import 'search_controller.dart';
import 'playback_controller.dart';
import 'navigation_controller.dart';
export 'managers/navigation_manager.dart';

import '../services/audio_handler_registry.dart';
class AudioProvider extends ChangeNotifier {
  final AudioPlayerService _playerService;
  final DatabaseService _dbService = DatabaseService.instance;
  final AudioFetchService _fetchService = AudioFetchService.instance;
  final LibraryController libraryController = LibraryController();
  final NavigationController navigationController = NavigationController();
  late final DownloadController downloadController;
  late final SearchController searchController;
  late final PlaybackController playbackController;

  // Playback state
  Track? _currentTrack;
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _duration = const Duration(seconds: 218);
  double _volume = 0.85;
  bool _isMuted = false;
  String _repeatMode = 'off'; // 'off' | 'all' | 'one'
  bool _isShuffle = false;
  List<Track> _queue = [];
  int _queueIndex = 0;
  final String _audioQuality = 'hi-fi';

  // User Settings (Default to true)
  bool _autoDownload = false;
  bool _autoPlayNext = true;

  // Navigation & Views
  AppView _activeView = AppView.home;
  final ValueNotifier<String?> pendingSearchQuery = ValueNotifier<String?>(null);
  Artist? _selectedArtist;
  Album? _selectedAlbum;
  Playlist? _selectedPlaylist;

  // Overlays
  bool _isFullPlayerOpen = false;
  bool _isQueueOpen = false;
  bool _isCreatePlaylistOpen = false;

  // Spectrum Visualizer
  List<double> _audioFrequencyData = List.filled(16, 15.0);
  Timer? _visualizerTimer;

  // Data Stores
  final UserProfile _user = mockCurrentUser;

  List<Track> _currentAlbumTracks = [];
  bool _isLoadingAlbumTracks = false;
  SearchEngineResponse? _lastSearchResults;

  // Downloading State
  final Map<String, double> _downloadProgress = {};
  bool _isDisposed = false;

  // Stream Retrieval State
  bool _isLoadingStream = false;
  String? _loadingTrackId;
  String _streamStatusMessage = '';
  int _currentPlayRequestId = 0;
  int _playbackTransitionId = 0;
  int? _handledCompletionTransitionId;
  String? _currentStreamUrl;

  bool get isLoadingStream => _isLoadingStream;
  String? get loadingTrackId => _loadingTrackId;
  String get streamStatusMessage => _streamStatusMessage;
  String? get currentStreamUrl => _currentStreamUrl;

  static const MethodChannel _voiceSearchChannel =
      MethodChannel('com.audiopulse/voice_search');

  // Subscriptions
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _handlerEventSub;
  AudioPulseHandler? _attachedHandler;

  AudioProvider([AudioPlayerService? playerService])
      : _playerService = playerService ?? AudioPlayerService() {
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final handler = audioHandler;
    if (isMobile && handler != null) {
      attachAudioHandler(handler);
    }

    downloadController = DownloadController(library: libraryController);
    searchController = SearchController(service: _fetchService.searchService);
    playbackController = PlaybackController(player: _playerService);
    downloadController.addListener(_relayDownloadProgress);
    _autoDownload = false;
    _autoPlayNext = true;
    _loadPreferences();
    _queue = List.from(mockTracks);
    if (_queue.isNotEmpty) {
      _currentTrack = _queue[0];
    }
    _initAudioService();
    _initVoiceSearchBridge();
    _loadTracksFromDatabase();
  }

  /// Attache les commandes Android Auto / MediaSession (`AudioPulseHandler`) au provider.
  void attachAudioHandler(AudioPulseHandler handler) {
    _handlerEventSub?.cancel();
    _attachedHandler = handler;

    handler.onPlay = () async {
      if (!_isPlaying) {
        await togglePlayPause();
      }
    };
    handler.onPause = () => pause();
    handler.onSkipToNext = () => playNext();
    handler.onSkipToPrevious = () => playPrevious();
    handler.onSkipToQueueItem = (index) => skipToQueueItem(index);
    handler.onPlayTrackWithQueue = (track, queue) => playTrack(track, queue);
    handler.onOnlineSearchFallback = (query) => searchOnline(query);
    handler.onResumeOrShuffleLibrary = () async {
      if (_currentTrack != null) {
        if (!_isPlaying) {
          await togglePlayPause();
        }
        return;
      }
      final tracks = libraryController.tracks;
      if (tracks.isNotEmpty) {
        final shuffled = List<Track>.from(tracks)..shuffle();
        await playTrack(shuffled.first, shuffled);
      }
    };

    _handlerEventSub = handler.customEvent.listen((event) {
      if (_isDisposed || event is! Map) return;
      final action = event['action'];
      if (action == 'playMediaId') {
        final mediaId = event['mediaId'] as String?;
        final eventQueue = event['queue'];
        final queueList = eventQueue is List<Track> ? eventQueue : null;
        if (mediaId != null) {
          final track = libraryController.trackById(mediaId);
          if (track != null) {
            unawaited(playTrack(track, queueList));
          }
        }
      } else if (action == 'skipToNext') {
        unawaited(playNext());
      } else if (action == 'skipToPrevious') {
        unawaited(playPrevious());
      } else if (action == 'skipToQueueItem') {
        final index = event['index'];
        if (index is int) {
          unawaited(skipToQueueItem(index));
        }
      }
    });

    _syncHandlerQueue();
  }

  void _syncHandlerQueue() {
    final handler = _attachedHandler ??
        ((!kIsWeb && (Platform.isAndroid || Platform.isIOS)) ? audioHandler : null);
    handler?.syncQueue(_queue, currentIndex: _queueIndex);
  }

  void _initVoiceSearchBridge() {
    if (kIsWeb || !Platform.isAndroid) return;
    _voiceSearchChannel.setMethodCallHandler((call) async {
      if (_isDisposed) return null;
      if (call.method == 'onVoiceSearch' && call.arguments is Map) {
        await _dispatchNativeVoicePayload(call.arguments as Map);
      }
      return null;
    });
  }

  Future<void> _consumePendingVoiceSearchIfAny() async {
    if (_isDisposed || kIsWeb || !Platform.isAndroid) return;
    try {
      final pending = await _voiceSearchChannel.invokeMethod<Map<dynamic, dynamic>>(
        'consumePendingVoiceSearch',
      );
      if (pending != null && !_isDisposed) {
        await _dispatchNativeVoicePayload(pending);
      }
    } on MissingPluginException {
      // Canal absent hors environnement Android natif.
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AudioProvider] consumePendingVoiceSearch error: $e');
      }
    }
  }

  Future<void> _dispatchNativeVoicePayload(Map<dynamic, dynamic> rawPayload) async {
    final query = (rawPayload['query'] as String?) ?? '';
    final rawExtras = rawPayload['extras'];
    final extras = <String, dynamic>{};
    if (rawExtras is Map) {
      rawExtras.forEach((key, value) {
        if (key != null && value != null) {
          extras[key.toString()] = value;
        }
      });
    }
    final handler = _attachedHandler ?? audioHandler;
    if (handler != null) {
      await handler.playFromSearch(query, extras.isEmpty ? null : extras);
    }
  }

  void _relayDownloadProgress() {
    if (_isDisposed) return;
    _downloadProgress
      ..clear()
      ..addAll(downloadController.progress);
    notifyListeners();
  }

  Future<void> _loadTracksFromDatabase() async {
    if (_isDisposed) return;
    try {
      await libraryController.refresh();
      if (_isDisposed) return;
      final tracks = libraryController.tracks;
      _queue = List.from(tracks);
      if (tracks.isNotEmpty && _currentTrack == null) {
        _currentTrack = tracks.first;
        _queueIndex = 0;
      }
      _syncHandlerQueue();
      notifyListeners();
    } catch (e) {
      if (_isDisposed) return;
      if (kDebugMode) debugPrint('Database load error, using fallback mock: $e');
      if (_queue.isEmpty) _queue = List.from(mockTracks);
      if (_currentTrack == null && _queue.isNotEmpty) {
        _currentTrack = _queue.first;
      }
      _syncHandlerQueue();
      notifyListeners();
    }
    await _consumePendingVoiceSearchIfAny();
  }

  void _initAudioService() {
    _posSub = _playerService.positionStream.listen((pos) {
      final prevSeconds = _currentPosition.inSeconds;
      _currentPosition = pos;
      // N'émet notifyListeners() que lorsque la seconde affichée change ou lors d'une remise à zéro,
      // évitant les rebuilds continus à haute fréquence (~5-10 Hz) sur tout l'arbre de widgets.
      if (pos.inSeconds != prevSeconds || pos == Duration.zero) {
        notifyListeners();
      }
    });

    _durSub = _playerService.durationStream.listen((dur) {
      if (_currentTrack != null && _currentTrack!.duration > 0) {
        // Always trust exact track metadata duration over AVPlayer/ExoPlayer container estimation
        _duration = Duration(seconds: _currentTrack!.duration);
      } else if (dur != null && dur > Duration.zero) {
        _duration = dur;
      }
      notifyListeners();
    });

    _stateSub = _playerService.playerStateStream.listen((state) {
      final playing = state.playing;
      final processingState = state.processingState;

      if (_isPlaying != playing) {
        _isPlaying = playing;
        if (_isPlaying) {
          // Clear any lingering status/error message once audio is actually playing
          _streamStatusMessage = '';
          _isLoadingStream = false;
          _loadingTrackId = null;
          _startVisualizerSimulation();
          // A new playing state arms the next completion event. This also
          // re-arms repeat-one playback after seek(0) + play().
          _handledCompletionTransitionId = null;
        } else {
          _stopVisualizerSimulation();
        }
        notifyListeners();
      }

      if (processingState == ProcessingState.completed) {
        unawaited(_handlePlaybackCompleted());
      }
    });
  }

  Future<void> _handlePlaybackCompleted() async {
    if (_isDisposed || _handledCompletionTransitionId == _playbackTransitionId) return;
    _handledCompletionTransitionId = _playbackTransitionId;
    try {
      if (_autoPlayNext) {
        await playNext();
      } else {
        await pause();
      }
    } catch (e) {
      if (_isDisposed) return;
      _streamStatusMessage = 'Erreur de fin de lecture';
      if (kDebugMode) debugPrint('[AudioProvider] completion transition failed: $e');
      notifyListeners();
    }
  }

  // Getters
  Track? get currentTrack => _currentTrack;
  bool get isPlaying => _isPlaying;
  Duration get currentPosition => _currentPosition;
  Duration get duration => _duration;
  double get volume => _volume;
  bool get isMuted => _isMuted;
  String get repeatMode => _repeatMode;
  bool get isShuffle => _isShuffle;
  List<Track> get queue => List.unmodifiable(_queue);
  int get queueIndex => _queueIndex;
  String get audioQuality => _audioQuality;
  String get activeView => _activeView.id;
  AppView get activeAppView => _activeView;
  Artist? get selectedArtist => _selectedArtist;
  Album? get selectedAlbum => _selectedAlbum;
  Playlist? get selectedPlaylist => _selectedPlaylist;

  Track? findLocalTrack(Track track) {
    // Identification stricte par ID unique du morceau
    for (final t in libraryController.tracks) {
      if (t.id == track.id) return t;
    }
    return null;
  }
  bool get isFullPlayerOpen => _isFullPlayerOpen;
  bool get isQueueOpen => _isQueueOpen;
  bool get isCreatePlaylistOpen => _isCreatePlaylistOpen;
  List<double> get audioFrequencyData => List.unmodifiable(_audioFrequencyData);
  List<Track> get allTracks => libraryController.tracks;
  List<Playlist> get allPlaylists => libraryController.playlists;
  UserProfile get user => _user;
  List<Track> get currentAlbumTracks => _currentAlbumTracks;
  bool get isLoadingAlbumTracks => _isLoadingAlbumTracks;
  SearchEngineResponse? get lastSearchResults => _lastSearchResults;
  Map<String, double> get downloadProgress => _downloadProgress;

  // Settings Getters & Toggles
  bool get autoDownload => _autoDownload;
  bool get autoPlayNext => _autoPlayNext;

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_isDisposed) return;
      _autoDownload = prefs.getBool('pref_auto_download') ?? false;
      _autoPlayNext = prefs.getBool('pref_auto_play_next') ?? true;
      notifyListeners();
    } catch (_) {}
  }

  void setAutoDownload(bool val) {
    _autoDownload = val;
    notifyListeners();
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool('pref_auto_download', val))
        .catchError((_) => false);
  }

  void toggleAutoDownload() {
    setAutoDownload(!_autoDownload);
  }

  void setAutoPlayNext(bool val) {
    _autoPlayNext = val;
    notifyListeners();
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool('pref_auto_play_next', val))
        .catchError((_) => false);
  }

  void toggleAutoPlayNext() {
    setAutoPlayNext(!_autoPlayNext);
  }

  Future<void> pause() async {
    if (_isDisposed) return;
    await _playerService.pause();
  }

  // Visualizer simulator (désactivé par défaut pour préserver la batterie et éviter 10 rebuilds/s inutiles)
  void _startVisualizerSimulation() {
    _visualizerTimer?.cancel();
    _visualizerTimer = null;
  }

  void _stopVisualizerSimulation() {
    _visualizerTimer?.cancel();
    _visualizerTimer = null;
    _audioFrequencyData = List.filled(16, 8.0);
  }

  // Navigation Setters
  void setActiveView(dynamic view) {
    if (view is AppView) {
      _activeView = view;
    } else if (view is String) {
      _activeView = AppView.fromString(view);
    }
    navigationController.setView(_activeView);
    notifyListeners();
  }

  void navigateToSearchWithQuery(String query) {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return;
    pendingSearchQuery.value = cleanQuery;
    setActiveView(AppView.search);
  }

  void setSelectedArtist(Artist artist) {
    _selectedArtist = artist;
    navigationController.selectArtist(artist);
    notifyListeners();
  }

  void setSelectedAlbum(Album album) {
    _selectedAlbum = album;
    navigationController.selectAlbum(album);
    notifyListeners();
  }

  void setSelectedPlaylist(Playlist playlist) {
    _selectedPlaylist = playlist;
    navigationController.selectPlaylist(playlist);
    notifyListeners();
  }

  void setIsFullPlayerOpen(bool isOpen) {
    _isFullPlayerOpen = isOpen;
    navigationController.setFullPlayerOpen(isOpen);
    notifyListeners();
  }

  void setIsQueueOpen(bool isOpen) {
    _isQueueOpen = isOpen;
    navigationController.setQueueOpen(isOpen);
    notifyListeners();
  }

  void setIsCreatePlaylistOpen(bool isOpen) {
    _isCreatePlaylistOpen = isOpen;
    notifyListeners();
  }

  /// Indique si le geste/bouton Retour Android peut quitter l'application
  /// (vrai uniquement sur l'écran d'accueil sans aucun panneau superposé).
  bool get canPopRoot =>
      !_isQueueOpen &&
      !_isFullPlayerOpen &&
      !_isCreatePlaylistOpen &&
      _activeView == AppView.home;

  /// Intercepte le geste/bouton Retour Android selon la hiérarchie visuelle :
  /// 1. Tiroir de file d'attente (`QueueDrawer`)
  /// 2. Lecteur plein écran (`FullScreenPlayer`)
  /// 3. Modale de création de playlist
  /// 4. Page Artiste -> retour à la Recherche
  /// 5. Tout autre onglet -> retour à la Bibliothèque (`AppView.home`)
  bool handleBackNavigation() {
    if (_isQueueOpen) {
      setIsQueueOpen(false);
      return true;
    }
    if (_isFullPlayerOpen) {
      setIsFullPlayerOpen(false);
      return true;
    }
    if (_isCreatePlaylistOpen) {
      setIsCreatePlaylistOpen(false);
      return true;
    }
    if (_activeView == AppView.artist) {
      setActiveView(AppView.search);
      return true;
    }
    if (_activeView != AppView.home) {
      setActiveView(AppView.home);
      return true;
    }
    return false;
  }

  // Playback Control Actions
  Future<void> playTrack(Track track, [List<Track>? newQueue]) async {
    if (kDebugMode && AudioPlayerService.enableAudioLogs) {
      debugPrint('[AudioProvider] 🕵️‍♂️ appel de playTrack avec: ${track.title}\nStackTrace:\n${StackTrace.current}');
    }
    
    if (_isDisposed) return;

    // Every request owns a transition. Older resolutions may finish, but they
    // can no longer install a source or start playback for the old track.
    final requestId = ++_currentPlayRequestId;
    final transitionId = ++_playbackTransitionId;
    _handledCompletionTransitionId = null;

    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    if (isMobile) {
      audioHandler?.notifyTrackLoading(
        MediaItem(
          id: track.id,
          album: track.album.isNotEmpty ? track.album : 'Single',
          title: track.title,
          artist: track.artist,
          artUri: track.coverUrl.isNotEmpty ? Uri.tryParse(track.coverUrl) : null,
          duration: track.duration > 0 ? Duration(seconds: track.duration) : null,
        ),
      );
    }

    // Stop any existing playback through the same serialized command queue.
    try {
      await _playerService.stop();
    } catch (e) {
      if (_isDisposed) return;
      _streamStatusMessage = 'Erreur d\'arrêt audio';
      if (kDebugMode) debugPrint('[AudioProvider] stop before transition failed: $e');
      audioHandler?.clearTransitionState();
      notifyListeners();
      return;
    }

    final existingTrack = libraryController.trackById(track.id);
    var effectiveTrack = (existingTrack != null && existingTrack.isDownloaded) ? existingTrack : track;

    if (!effectiveTrack.isDownloaded) {
      final localFile = await _fetchService.streamResolver.findExistingDownloadedFile(effectiveTrack);
      if (localFile != null) {
        effectiveTrack = effectiveTrack.copyWith(
          isDownloaded: true,
          localFilePath: localFile,
        );
      }
    }

    _currentTrack = effectiveTrack;
    _currentPosition = Duration.zero;
    _duration = Duration(seconds: effectiveTrack.duration > 0 ? effectiveTrack.duration : 200);

    if (newQueue != null && newQueue.isNotEmpty) {
      _queue = List.from(newQueue);
      _queueIndex = _queue.indexWhere((t) => t.id == effectiveTrack.id);
      if (_queueIndex == -1) _queueIndex = 0;
    } else if (_queue.isNotEmpty) {
      final existingIdx = _queue.indexWhere((t) => t.id == effectiveTrack.id);
      if (existingIdx != -1) {
        _queueIndex = existingIdx;
      }
    }
    _syncHandlerQueue();

    _isLoadingStream = true;
    _loadingTrackId = effectiveTrack.id;
    _streamStatusMessage = 'Chargement audio...';
    notifyListeners();

    // Persist or update track through the single library source (persists to
    // SQLite and updates the in-memory cache).
    unawaited(libraryController.upsertTrack(effectiveTrack).catchError((_) {}));

    // Indexer l'artiste et son ID en base locale
    unawaited(_dbService.saveArtistIndex(effectiveTrack.artist, artistId: effectiveTrack.artistId));

    // --- RÉSOLUTION JUST-IN-TIME (Fantômes Apple Music) ---
    if (effectiveTrack.source == 'apple_import' || (effectiveTrack.audioUrl.isEmpty && effectiveTrack.coverUrl.isEmpty)) {
      _streamStatusMessage = 'Résolution haute qualité...';
      notifyListeners();
      try {
        final query = "${effectiveTrack.artist} - ${effectiveTrack.title} - ${effectiveTrack.album}";
        final response = await _fetchService.searchCatalog(query);
        final topTracks = response.tracks.where((t) => t.source == 'music').toList();
        
        if (topTracks.isNotEmpty) {
          final officialTrack = topTracks.first;
          effectiveTrack = effectiveTrack.copyWith(
            title: officialTrack.title,
            artist: officialTrack.artist,
            album: officialTrack.album,
            coverUrl: officialTrack.coverUrl,
            audioUrl: officialTrack.audioUrl,
            duration: officialTrack.duration,
            artistId: officialTrack.artistId.isNotEmpty ? officialTrack.artistId : effectiveTrack.artistId,
            albumId: officialTrack.albumId.isNotEmpty ? officialTrack.albumId : effectiveTrack.albumId,
            source: 'music', // Résolu ! Ne sera plus fantôme.
            ambientColor: officialTrack.ambientColor,
          );
          
          _currentTrack = effectiveTrack;
          _duration = Duration(seconds: effectiveTrack.duration > 0 ? effectiveTrack.duration : 200);
          
          if (_queueIndex >= 0 && _queueIndex < _queue.length) {
            _queue[_queueIndex] = effectiveTrack;
          }
          
          // Met à jour la base de données avec les vraies informations
          unawaited(libraryController.upsertTrack(effectiveTrack).catchError((_) {}));
          
          // Sauvegarde également le vrai album si récupéré
          if (officialTrack.albumId.isNotEmpty) {
             final newAlbum = Album(
                  id: officialTrack.albumId, title: officialTrack.album, artist: officialTrack.artist,
                  artistId: officialTrack.artistId, coverUrl: officialTrack.coverUrl,
                  releaseYear: officialTrack.releaseYear, tracksCount: 1, genre: officialTrack.genre,
                  ambientColor: officialTrack.ambientColor,
              );
              unawaited(_dbService.saveAlbumsIndex([newAlbum]));
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[AudioProvider] Erreur lors de la résolution JIT : $e');
      }
    }

    final sw = Stopwatch()..start();
    try {
      if (kDebugMode && AudioPlayerService.enableAudioLogs) {
        debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        debugPrint('[AudioProvider] 🎶 [1/4] Démarrage: "${effectiveTrack.title}" par "${effectiveTrack.artist}" (id: ${effectiveTrack.id})');
      }

      final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
      final mediaItem = isMobile
          ? MediaItem(
              id: effectiveTrack.id,
              album: effectiveTrack.album.isNotEmpty ? effectiveTrack.album : 'Single',
              title: effectiveTrack.title,
              artist: effectiveTrack.artist,
              artUri: effectiveTrack.coverUrl.isNotEmpty ? Uri.tryParse(effectiveTrack.coverUrl) : null,
              duration: effectiveTrack.duration > 0 ? Duration(seconds: effectiveTrack.duration) : null,
            )
          : null;

      if (isMobile && mediaItem != null) {
        audioHandler?.notifyTrackLoading(mediaItem);
      }

      final sourceLoaded = await _loadSourceWithRetry(effectiveTrack, mediaItem, requestId);
      if (!sourceLoaded) {
        if (requestId == _currentPlayRequestId) {
          audioHandler?.clearTransitionState();
        }
        if (kDebugMode && AudioPlayerService.enableAudioLogs) {
          debugPrint('[AudioProvider] ⚠️ Lecture annulée: impossible d\'obtenir un flux valide pour "${effectiveTrack.title}".');
        }
        return;
      }
      if (_isDisposed || requestId != _currentPlayRequestId || transitionId != _playbackTransitionId) return;

      await _playerService.play();
      if (!_isDisposed && requestId == _currentPlayRequestId && transitionId == _playbackTransitionId) {
        _streamStatusMessage = 'Lecture en cours';
        if (kDebugMode && AudioPlayerService.enableAudioLogs) {
          debugPrint('[Performance] ⚡ Total clic ➔ son : ${sw.elapsedMilliseconds} ms');
          debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        }

        // Auto-download track in background for offline use if enabled
        if (kDebugMode && AudioPlayerService.enableAudioLogs) {
          debugPrint('[AutoDownload] ⚙️ Options: autoDownload=$_autoDownload | isDownloaded=${effectiveTrack.isDownloaded} | localFile=${effectiveTrack.localFilePath}');
        }
        if (_autoDownload && !effectiveTrack.isDownloaded) {
          if (kDebugMode) debugPrint('[AutoDownload] 📥 Lancement du téléchargement en arrière-plan pour "${effectiveTrack.title}"...');
          unawaited(toggleDownload(effectiveTrack.id, effectiveTrack).catchError((e) {
            if (kDebugMode) debugPrint('[AutoDownload] ⚠️ Erreur auto-téléchargement: $e');
          }));
        }
      }
    } catch (e, st) {
      if (!_isDisposed && requestId == _currentPlayRequestId && transitionId == _playbackTransitionId) {
        audioHandler?.clearTransitionState();
        if (kDebugMode && AudioPlayerService.enableAudioLogs) {
          debugPrint('[AudioProvider] ❌ playTrack error en ${sw.elapsedMilliseconds} ms: $e\n$st');
        }
        _streamStatusMessage = 'Erreur de lecture';
      }
    } finally {
      if (!_isDisposed && requestId == _currentPlayRequestId && transitionId == _playbackTransitionId) {
        _isLoadingStream = false;
        _loadingTrackId = null;
        notifyListeners();
      }
    }
  }

  // Stub retained for Flutter VM Hot Reload compatibility
  @pragma('vm:entry-point')
  void _startBackgroundCache(Track track) {}

  /// Résout puis charge la source audio de façon résiliente avec annulation immédiate si un autre morceau est cliqué.
  Future<bool> _loadSourceWithRetry(Track track, MediaItem? mediaItem, int requestId) async {
    if (_isDisposed || requestId != _currentPlayRequestId) return false;
    try {
      final resolveSw = Stopwatch()..start();
      final source = await _fetchService.resolveAudioSource(
        track,
        tag: mediaItem,
        onBitrateResolved: (bitrate) {
          if (_isDisposed || requestId != _currentPlayRequestId) return;
          bool changed = false;
          if (_currentTrack != null && _currentTrack!.id == track.id && _currentTrack!.bitrate != bitrate) {
            _currentTrack = _currentTrack!.copyWith(bitrate: bitrate);
            changed = true;
            unawaited(libraryController.upsertTrack(_currentTrack!).catchError((_) {}));
          }
          if (changed && !kIsWeb && (Platform.isAndroid || Platform.isIOS) && mediaItem != null) {
            audioHandler?.mediaItem.add(mediaItem);
          }
          final qIdx = _queue.indexWhere((t) => t.id == track.id);
          if (qIdx != -1 && _queue[qIdx].bitrate != bitrate) {
            _queue[qIdx] = _queue[qIdx].copyWith(bitrate: bitrate);
            changed = true;
          }
          if (changed) {
            notifyListeners();
          }
        },
      );
      final resolveTime = resolveSw.elapsedMilliseconds;
      if (kDebugMode) debugPrint('[Performance] ⏱️ resolveAudioSource a pris $resolveTime ms');
      
      if (_isDisposed || requestId != _currentPlayRequestId) return false;
      
      if (source == null) {
        _streamStatusMessage = 'Morceau indisponible ou restreint';
        notifyListeners();
        if (kDebugMode && AudioPlayerService.enableAudioLogs) {
          debugPrint('[AudioProvider] ❌ Impossible de résoudre le flux natif pour "${track.title}" (${track.id}).');
        }
        return false;
      }
      
      _streamStatusMessage = 'Préparation du lecteur...';
      notifyListeners();
      
      final playerSw = Stopwatch()..start();
      await _playerService.setAudioSource(source, track: track);
      final playerTime = playerSw.elapsedMilliseconds;
      if (kDebugMode) debugPrint('[Performance] ⏱️ setAudioSource (moteur AVPlayer) a pris $playerTime ms');
      return true;
    } catch (e, st) {
      if (kDebugMode && AudioPlayerService.enableAudioLogs) {
        debugPrint('[AudioProvider] ⚠️ Erreur native de lecture pour ${track.title}: $e\n$st');
      }
      _streamStatusMessage = 'Erreur technique de lecture';
      notifyListeners();
      return false;
    }
  }

  Future<void> togglePlayPause() async {
    if (_isDisposed) return;
    if (_isPlaying) {
      await _playerService.pause();
    } else {
      if (_currentTrack != null &&
          (_playerService.player.processingState == ProcessingState.idle ||
              _playerService.player.audioSource == null)) {
        await playTrack(_currentTrack!);
      } else {
        await _playerService.play();
      }
    }
  }

  Future<void> seek(Duration position) async {
    if (_isDisposed) return;
    await _playerService.seek(position);
  }

  Future<void> setVolumeLevel(double vol) async {
    _volume = vol.clamp(0.0, 1.0);
    if (_volume > 0 && _isMuted) {
      _isMuted = false;
    }
    await _playerService.setVolume(_isMuted ? 0.0 : _volume);
    notifyListeners();
  }

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    await _playerService.setVolume(_isMuted ? 0.0 : _volume);
    notifyListeners();
  }

  Future<void> playNext() async {
    if (_isDisposed) return;
    if (_queue.isEmpty) return;

    if (_repeatMode == 'one') {
      await seek(Duration.zero);
      await _playerService.play();
      return;
    }

    int nextIdx = _queueIndex + 1;
    if (_isShuffle) {
      final rand = Random();
      nextIdx = rand.nextInt(_queue.length);
    }

    if (nextIdx < _queue.length) {
      _queueIndex = nextIdx;
      await playTrack(_queue[nextIdx]);
    } else if (_repeatMode == 'all') {
      _queueIndex = 0;
      await playTrack(_queue[0]);
    } else {
      await _playerService.pause();
    }
  }

  Future<void> playPrevious() async {
    if (_isDisposed) return;
    if (_currentPosition.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    final prevIdx = _queueIndex - 1;
    if (prevIdx >= 0) {
      _queueIndex = prevIdx;
      await playTrack(_queue[prevIdx]);
    } else {
      await seek(Duration.zero);
    }
  }

  void toggleRepeat() {
    const modes = ['off', 'all', 'one'];
    final currentIndex = modes.indexOf(_repeatMode);
    _repeatMode = modes[(currentIndex + 1) % modes.length];
    notifyListeners();
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    notifyListeners();
  }

  Future<void> skipToQueueItem(int index) async {
    if (_isDisposed || index < 0 || index >= _queue.length) return;
    _queueIndex = index;
    await playTrack(_queue[index]);
  }

  // Queue Management
  void removeFromQueue(int index) {
    if (index >= 0 && index < _queue.length) {
      _queue.removeAt(index);
      if (index < _queueIndex) {
        _queueIndex--;
      }
      _syncHandlerQueue();
      notifyListeners();
    }
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length || newIndex < 0 || newIndex > _queue.length) return;
    
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    
    final Track? activeTrack = (_queueIndex >= 0 && _queueIndex < _queue.length) ? _queue[_queueIndex] : _currentTrack;
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);
    
    if (activeTrack != null) {
      final newIdx = _queue.indexWhere((t) => t.id == activeTrack.id);
      if (newIdx != -1) {
        _queueIndex = newIdx;
      }
    }
    _syncHandlerQueue();
    notifyListeners();
  }

  void moveQueueItemUp(int index) {
    if (index > 0 && index < _queue.length) {
      reorderQueue(index, index - 1);
    }
  }

  void moveQueueItemDown(int index) {
    if (index >= 0 && index < _queue.length - 1) {
      reorderQueue(index, index + 2);
    }
  }

  void addToQueue(Track track) {
    _queue.add(track);
    _syncHandlerQueue();
    notifyListeners();
  }

  void playNextTrack(Track track) {
    if (_queue.isEmpty || _queueIndex < 0) {
      _queue = [?_currentTrack, track];
      _queueIndex = 0;
    } else {
      final insertIndex = (_queueIndex + 1).clamp(0, _queue.length);
      _queue.insert(insertIndex, track);
    }
    _syncHandlerQueue();
    notifyListeners();
  }

  void clearQueue() {
    _queue.clear();
    _queueIndex = 0;
    _syncHandlerQueue();
    notifyListeners();
  }

  // Search Live YouTube & Online Music
  Future<List<Track>> searchOnline(String query) async {
    if (query.trim().isEmpty) return [];
    return await _fetchService.searchOnlineTracks(query);
  }

  Future<SearchEngineResponse> searchCatalogOnline(String query) async {
    if (query.trim().isEmpty) {
      searchController.clear();
      return SearchEngineResponse.empty();
    }
    await searchController.search(query);
    if (searchController.status == SearchStatus.error) {
      throw searchController.error!;
    }
    final results = searchController.results;
    _lastSearchResults = results;

    // Indexer immédiatement les artistes et albums croisés lors de la recherche
    for (final artist in results.artists) {
      unawaited(_dbService.saveArtistIndex(artist.name, artistId: artist.id, avatarUrl: artist.avatarUrl));
    }
    for (final track in results.tracks) {
      unawaited(_dbService.saveArtistIndex(track.artist, artistId: track.artistId));
    }
    if (results.albums.isNotEmpty) {
      unawaited(_dbService.saveAlbumsIndex(results.albums));
    }

    notifyListeners();
    return results;
  }

  Future<({String title, String logoUrl, String bannerUrl})?> getChannelDetails(String channelId) async {
    return await _fetchService.getChannelDetails(channelId);
  }

  Future<({String title, String logoUrl, String bannerUrl})?> getArtistChannelDetails(
    String artistName, {
    String artistId = '',
  }) async {
    return await _fetchService.getArtistChannelDetails(artistName, artistId: artistId);
  }

  Future<({List<Album> releases, List<Album> playlists})> getArtistReleasesAndPlaylists(
    String artistName, {
    String artistId = '',
    int limit = 6,
  }) async {
    return await _fetchService.getArtistReleasesAndPlaylists(artistName, artistId: artistId, limit: limit);
  }

  void selectArtistAndNavigate(Artist artist) {
    _selectedArtist = artist;
    _activeView = AppView.artist;
    notifyListeners();
  }

  void selectAlbumAndNavigate(Album album) {
    _selectedAlbum = album;
    notifyListeners();
  }

  Track _placeholderTrack(String trackId) {
    return Track(
      id: trackId,
      title: 'Piste',
      artist: 'Artiste',
      album: 'Single',
      duration: 180,
      coverUrl: '',
      audioUrl: 'yt://$trackId',
      genre: 'Hi-Fi',
    );
  }

  // Local Download & File Storage Action (routes through DownloadController)
  Future<void> toggleDownload(String trackId, [Track? explicitTrack]) async {
    if (_isDisposed) return;
    final Track current = explicitTrack ??
        libraryController.trackById(trackId) ??
        (_currentTrack?.id == trackId
            ? _currentTrack!
            : (_queue.firstWhere((t) => t.id == trackId,
                    orElse: () => _lastSearchResults?.tracks.firstWhere(
                          (t) => t.id == trackId,
                          orElse: () => _placeholderTrack(trackId),
                        ) ??
                        _placeholderTrack(trackId))));

    if (current.isDownloaded) {
      if (current.localFilePath != null) {
        try {
          final file = File(current.localFilePath!);
          if (await file.exists()) await file.delete();
        } catch (e) {
          if (kDebugMode) debugPrint('audio_provider: local file delete failed: $e');
        }
      }
      await libraryController.setDownload(trackId, null, false);
      _queue = _queue.map((t) => t.id == trackId ? t.copyWith(isDownloaded: false, clearLocalFilePath: true) : t).toList();
      if (_currentTrack?.id == trackId) {
        _currentTrack = _currentTrack!.copyWith(isDownloaded: false, clearLocalFilePath: true);
      }
      notifyListeners();
      return;
    }

    final downloaded = await downloadController.download(current);
    if (downloaded == null || _isDisposed) {
      notifyListeners();
      return;
    }

    Track updatedTrack = downloaded;
    final artistName = current.artist.trim();
    final artistId = current.artistId.trim();

    // Enrich metadata (including artistAvatarUrl) via artistId or artistName fallback.
    if (artistName.isNotEmpty || artistId.isNotEmpty) {
      try {
        final channelDetails = await _fetchService.getArtistChannelDetails(
          artistName,
          artistId: artistId,
        );
        if (channelDetails != null && channelDetails.logoUrl.isNotEmpty) {
          final effectiveArtistId = artistId.isNotEmpty
              ? artistId
              : 'artist_${artistName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
          updatedTrack = updatedTrack.copyWith(
            artistAvatarUrl: channelDetails.logoUrl,
          );
          await _dbService.insertOrUpdateArtist(Artist(
            id: effectiveArtistId,
            name: channelDetails.title.isNotEmpty ? channelDetails.title : artistName,
            avatarUrl: channelDetails.logoUrl,
            bannerUrl: channelDetails.bannerUrl,
            bio: 'Artiste Officiel',
            tracks: [],
            albums: [],
          ));
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Error saving artist details: $e');
      }
      if (artistId.isNotEmpty) {
        try {
          final discography = await _fetchService.getArtistReleasesAndPlaylists(artistName, artistId: artistId);
          for (final release in discography.releases) {
            await _dbService.insertOrUpdateAlbum(release);
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Error saving artist releases: $e');
        }
      }
    }

    try {
      final match = await _fetchService.findMatchingReleaseTrack(current);
      if (match.matchedTrack != null && match.matchedAlbum != null) {
        updatedTrack = updatedTrack.copyWith(
          album: match.matchedAlbum!.title,
          albumId: match.matchedAlbum!.id,
          coverUrl: match.matchedAlbum!.coverUrl,
          artistId: artistId.isNotEmpty ? artistId : match.matchedAlbum!.artistId,
        );
        await _dbService.insertOrUpdateAlbum(match.matchedAlbum!);
      } else if (current.album.isNotEmpty && current.album != 'Streaming Web' && current.album != 'Single') {
        final generatedAlbumId = 'album_${artistName}_${current.album}'.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
        updatedTrack = updatedTrack.copyWith(albumId: generatedAlbumId);
        await _dbService.insertOrUpdateAlbum(Album(
          id: generatedAlbumId,
          title: current.album,
          artist: artistName,
          artistId: artistId,
          coverUrl: current.coverUrl,
          releaseYear: DateTime.now().year,
          tracksCount: 1,
          genre: current.genre,
          ambientColor: current.ambientColor,
          tracks: [],
        ));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error detecting track album on download: $e');
    }

    await libraryController.upsertTrack(updatedTrack);
    _queue = _queue.map((t) => t.id == trackId ? updatedTrack : t).toList();
    if (_currentTrack?.id == trackId) {
      _currentTrack = updatedTrack;
    }
    notifyListeners();
  }

  // Favorite toggle
  Future<void> toggleFavorite(String trackId) async {
    if (_isDisposed) return;
    final track = libraryController.trackById(trackId);
    if (track == null) return;
    final isFav = !track.isFavorite;
    await libraryController.setFavorite(trackId, isFav);
    if (_currentTrack?.id == trackId) {
      _currentTrack = _currentTrack!.copyWith(isFavorite: isFav);
    }
    notifyListeners();
  }

  // Téléchargement complet d'un album ou d'une playlist
  Future<void> downloadAlbum(Album album) async {
    List<Track> tracksToDownload = album.tracks;
    if (tracksToDownload.isEmpty) {
      final details = await _fetchService.fetchAlbumDetailsAndTracks(Track(
        id: album.id,
        title: album.title,
        artist: album.artist,
        album: album.title,
        coverUrl: album.coverUrl,
        audioUrl: 'yt://${album.id}',
        duration: 180,
        genre: album.genre,
        ambientColor: album.ambientColor,
      ));
      tracksToDownload = details.tracks;
    }

    for (final track in tracksToDownload) {
      final isAlready = libraryController.tracks.any((t) => (t.id == track.id || t.title.toLowerCase() == track.title.toLowerCase()) && t.isDownloaded);
      if (!isAlready) {
        await toggleDownload(track.id, track);
      }
    }
  }

  // Playlist Management
  Future<void> createNewPlaylist(String title, String description) async {
    if (_isDisposed) return;
    await libraryController.createPlaylist(title, description);
    notifyListeners();
  }

  Future<void> addTrackToUserPlaylist(String playlistId, Track track) async {
    if (_isDisposed) return;
    final added = await libraryController.addToPlaylist(playlistId, track);
    if (added) notifyListeners();
  }

  Future<void> loadAlbumTracks(Track track) async {
    _isLoadingAlbumTracks = true;
    _currentAlbumTracks = [];
    notifyListeners();

    try {
      final result = await _fetchService.fetchAlbumDetailsAndTracks(track);
      _currentAlbumTracks = result.tracks;

      if (result.albumName != null && _currentTrack?.id == track.id) {
        final updated = _currentTrack!.copyWith(album: result.albumName!);
        _currentTrack = updated;
        await libraryController.upsertTrack(updated);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading album tracks: $e');
    } finally {
      _isLoadingAlbumTracks = false;
      notifyListeners();
    }
  }

  Future<void> clearTracksAndCache() async {
    _queue = [];
    _currentAlbumTracks = [];
    _fetchService.clearCache();
    await _dbService.clearAllData();
    await libraryController.refresh();
    _syncHandlerQueue();
    notifyListeners();
  }

  Future<void> refreshTracksFromDatabase() async {
    if (_isDisposed) return;
    await libraryController.refresh();
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    unawaited(_posSub?.cancel() ?? Future<void>.value());
    unawaited(_durSub?.cancel() ?? Future<void>.value());
    unawaited(_stateSub?.cancel() ?? Future<void>.value());
    unawaited(_handlerEventSub?.cancel() ?? Future<void>.value());
    final handler = _attachedHandler;
    if (handler != null) {
      handler.onPlay = null;
      handler.onPause = null;
      handler.onSkipToNext = null;
      handler.onSkipToPrevious = null;
      handler.onSkipToQueueItem = null;
      handler.onPlayTrackWithQueue = null;
      handler.onResumeOrShuffleLibrary = null;
      handler.onOnlineSearchFallback = null;
      _attachedHandler = null;
    }
    _visualizerTimer?.cancel();
    pendingSearchQuery.dispose();
    _playerService.dispose();
    _fetchService.dispose();
    libraryController.dispose();
    navigationController.dispose();
    downloadController.dispose();
    searchController.dispose();
    playbackController.dispose();
    super.dispose();
  }
}
