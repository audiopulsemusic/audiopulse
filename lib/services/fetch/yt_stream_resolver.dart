// just_audio exposes the custom stream source API as experimental; this
// resolver intentionally uses it for controlled HTTP streaming.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../models/track.dart';
import '../database_service.dart';
import '../network/network_exception.dart';
import '../network/network_guard.dart';
import '../network/url_security_policy.dart';
import 'yt_utils.dart';

/// Source audio personnalisée servant les flux YouTube via le client HTTP Dart de YoutubeExplode
/// Évite tout problème d'incompatibilité de headers, cookies ou format AVPlayer natif
class YouTubeAudioSource extends StreamAudioSource {
  final StreamInfo streamInfo;
  final http.Client httpClient;
  static const int maxRangeChunkBytes = 256 * 1024;

  @visibleForTesting
  static ({int start, int endExclusive}) calculateRange(
    int start,
    int requestedEndExclusive,
    int totalSize,
  ) {
    if (totalSize <= 0 ||
        start < 0 ||
        requestedEndExclusive < start ||
        requestedEndExclusive > totalSize) {
      throw RangeError('Audio range [$start, $requestedEndExclusive) hors limites ($totalSize).');
    }
    return (
      start: start,
      endExclusive: math.min(requestedEndExclusive, start + maxRangeChunkBytes),
    );
  }

  Stream<List<int>> _createChunkedStream(int start, int endExclusive) async* {
    final request = http.Request('GET', streamInfo.url)
      ..followRedirects = true
      ..headers['Range'] = 'bytes=$start-${endExclusive - 1}'
      ..headers['User-Agent'] = BrowserHttpClient.userAgentFor(streamInfo.url)
      ..headers['Accept'] = '*/*';

    final http.StreamedResponse response;
    try {
      response = await httpClient.send(request).timeout(const Duration(seconds: 20));
    } catch (e) {
      if (kDebugMode) debugPrint('[YouTubeAudioSource] ❌ Exception réseau: $e');
      throw HttpException('Impossible de récupérer le flux audio YouTube: $e', uri: streamInfo.url);
    }

    if (kDebugMode) {
      debugPrint('━━━━━━━━━━━━━━━━ [YOUTUBE HTTP RESPONSE] ━━━━━━━━━━━━━━━━');
      debugPrint('Request Range: bytes=$start-${endExclusive - 1}');
      debugPrint('Status: ${response.statusCode}');
      response.headers.forEach((key, value) {
        debugPrint('  $key: $value');
      });
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    }

    if (response.statusCode != 206 && response.statusCode != 200) {
      await response.stream.drain<void>().catchError((_) {});
      throw HttpException(
        'Erreur HTTP ${response.statusCode} lors de la lecture du flux YouTube',
        uri: streamInfo.url,
      );
    }

    try {
      await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
        yield chunk;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[YouTubeAudioSource] ❌ Interruption du flux par YouTube: $e');
      throw HttpException('Interruption du flux audio YouTube: $e', uri: streamInfo.url);
    }
  }

  YouTubeAudioSource({
    required this.streamInfo,
    required this.httpClient,
    super.tag,
  });

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final totalSize = streamInfo.size.totalBytes;
    final rangeStart = start ?? 0;
    final requestedEndExclusive = end ?? totalSize;
    
    if (kDebugMode) {
      debugPrint('[YouTubeAudioSource] 🎧 AVPlayer demande les octets: $rangeStart - $requestedEndExclusive (Total: $totalSize)');
    }

    if (totalSize <= 0 ||
        rangeStart < 0 ||
        requestedEndExclusive < rangeStart ||
        requestedEndExclusive > totalSize) {
      if (kDebugMode) debugPrint('[YouTubeAudioSource] ❌ AVPlayer a demandé une plage invalide !');
      throw RangeError('Audio range [$rangeStart, $requestedEndExclusive) hors limites ($totalSize).');
    }
    final rangeLength = requestedEndExclusive - rangeStart;

    return StreamAudioResponse(
      rangeRequestsSupported: true,
      sourceLength: totalSize,
      contentLength: rangeLength,
      offset: rangeStart,
      stream: _createChunkedStream(rangeStart, requestedEndExclusive),
      contentType: streamInfo.container == StreamContainer.mp4 ? 'audio/mp4' : 'audio/webm',
    );
  }
}

/// Specialized service for audio stream URL resolution and downloading
class YtStreamResolver {
  final YoutubeExplode _client;
  final BrowserHttpClient _browserClient;

  // Stream URL cache (with expiration to avoid serving expired signed URLs)
  final Map<String, String> _resolvedStreamUrls = {};
  final Map<String, DateTime> _resolvedStreamTimes = {};
  final Map<String, Future<String?>> _resolvedInFlight = {};
  static const Duration _streamUrlTtl = Duration(minutes: 30);
  static const int _streamUrlCacheMax = 200;

  // Download safeguards: global concurrency limit, size ceiling, and name bound.
  static const int _maxConcurrentDownloads = 3;
  static const int _maxDownloadBytes = 200 * 1024 * 1024; // 200 MB
  static const int _maxNamePartLength = 40;
  final Set<String> _activeTrackDownloads = {};
  int _activeDownloads = 0;
  final Queue<Completer<void>> _downloadWaiters = Queue();

  // YouTube anti-abuse cooldown: after a timeout or rate-limit, skip native
  // manifest requests for a while and go straight to the Piped fallback. This
  // prevents a single clicking session from hammering YouTube's watch endpoint
  // and worsening the rate-limit (remains fully usable without authentication).
  DateTime _youtubeBlockedUntil = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _youtubeBlocked => DateTime.now().isBefore(_youtubeBlockedUntil);

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;
  bool get _isApple => !kIsWeb && (Platform.isMacOS || Platform.isIOS);

  void markYoutubeBlocked(Duration cooldown) {
    _markYoutubeBlocked(cooldown);
  }

  void _markYoutubeBlocked(Duration cooldown) {
    _youtubeBlockedUntil = DateTime.now().add(cooldown);
  }

  /// Selects a stream that the current platform can actually decode and seek smoothly.
  ///
  /// Progressive MP4 (Tag 18 with ratebypass=yes) has full AAC audio and 100% reliable
  /// seeking/streaming across AVPlayer (macOS, iOS) and Android without CDN throttling.
  StreamInfo? _selectPlatformAudioStream(StreamManifest manifest, {bool safeMode = false}) {
    // 🛡️ Mode anti-blocage : Tag 18 garanti sans 403 (ratebypass=yes)
    // Sur Apple (macOS/iOS) et en streaming, les requêtes Range complètes d'AVPlayer
    // échouent avec une 403 sur les flux audio purs non-ratebypass (Tag 140).
    // Tag 18 offre un flux AAC de même qualité (128 kbps) avec ratebypass=yes garanti.
    final ratebypassStreams = manifest.muxed.where(
      (stream) => (stream.tag == 18 || stream.url.toString().contains('ratebypass=yes')) && stream.container == StreamContainer.mp4,
    );
    if (ratebypassStreams.isNotEmpty) {
      return ratebypassStreams.first;
    }

    if (safeMode) {
      if (manifest.muxed.isNotEmpty) return manifest.muxed.withHighestBitrate();
    }

    if (_isApple) {
      // 1. Priorité : Audio pur MP4 / AAC
      final mp4AudioOnly = manifest.audioOnly.where(
        (stream) => stream.container == StreamContainer.mp4,
      );
      if (mp4AudioOnly.isNotEmpty) {
        return mp4AudioOnly.withHighestBitrate();
      }

      // 2. Si aucun MP4 audio pur, meilleur flux audio pur (ex: Opus/WebM)
      final anyAudio = manifest.audioOnly;
      if (anyAudio.isNotEmpty) {
        return anyAudio.withHighestBitrate();
      }

      // 3. Fallback : Flux muxé (vidéo + audio) avec le plus haut bitrate
      if (manifest.muxed.isNotEmpty) {
        return manifest.muxed.withHighestBitrate();
      }

      return null;
    }

    // Android, Web, Desktop non-Apple : Audio pur avec le plus haut bitrate
    final audioStreams = manifest.audioOnly;
    if (audioStreams.isNotEmpty) {
      return audioStreams.withHighestBitrate();
    }

    if (manifest.muxed.isNotEmpty) {
      return manifest.muxed.withHighestBitrate();
    }

    return null;
  }

  /// Sélectionne le flux audio avec la qualité studio maximale selon la plateforme.
  /// Priorise Tag 18 (AAC 128 kbps avec ratebypass) pour garantir l'absence d'erreur 403 / throttling.
  StreamInfo? _selectStudioAudioStream(StreamManifest manifest) {
    // 1. Flux MP4 garanti sans 403 (Tag 18 ou ratebypass=yes)
    final ratebypass = manifest.muxed.where(
      (stream) => (stream.tag == 18 || stream.url.toString().contains('ratebypass=yes')) && stream.container == StreamContainer.mp4,
    );
    if (ratebypass.isNotEmpty) {
      return ratebypass.first;
    }

    if (_isApple) {
      // 2. Audio pur MP4/M4A (Itag 140 - AAC-LC ~130-140 kbps)
      final mp4AudioOnly = manifest.audioOnly.where(
        (stream) => stream.container == StreamContainer.mp4,
      );
      if (mp4AudioOnly.isNotEmpty) {
        return mp4AudioOnly.withHighestBitrate();
      }
      // 3. Fallback MP4 muxé si audio-only absent
      final muxedMp4 = manifest.muxed.where(
        (stream) => stream.container == StreamContainer.mp4,
      );
      if (muxedMp4.isNotEmpty) {
        return muxedMp4.withHighestBitrate();
      }
      return null;
    }

    // Android, Web, Desktop non-Apple : Audio pur avec le plus haut bitrate (Itag 251 Opus ~160 kbps)
    final audioStreams = manifest.audioOnly;
    if (audioStreams.isNotEmpty) {
      return audioStreams.withHighestBitrate();
    }

    if (manifest.muxed.isNotEmpty) {
      return manifest.muxed.withHighestBitrate();
    }

    return null;
  }

  YtStreamResolver({
    YoutubeExplode? client,
    BrowserHttpClient? browserClient,
    http.Client? mediaHttpClient,
  })  : _client = client ?? YoutubeExplode(),
        _browserClient = browserClient ?? (mediaHttpClient is BrowserHttpClient ? mediaHttpClient : BrowserHttpClient());

  Future<void> _acquireDownloadSlot() async {
    if (_activeDownloads < _maxConcurrentDownloads) {
      _activeDownloads++;
      return;
    }
    final completer = Completer<void>();
    _downloadWaiters.add(completer);
    await completer.future;
  }

  void _releaseDownloadSlot() {
    if (_downloadWaiters.isNotEmpty) {
      final next = _downloadWaiters.removeFirst();
      next.complete();
    } else {
      _activeDownloads--;
    }
  }

  void clearCache() {
    _resolvedStreamUrls.clear();
    _resolvedStreamTimes.clear();
    _resolvedInFlight.clear();
  }

  /// Returns true only for HTTPS URLs whose host is not a local/private/internal
  /// address, to mitigate SSRF and traffic-in-cleartext risks.
  static bool isSafeStreamUrl(String url) {
    return UrlSecurityPolicy.isSafePublicHttps(url);
  }

  /// Résout l'identifiant YouTube d'un morceau
  Future<String?> resolveVideoId(Track track) async {
    final rawUrl = track.audioUrl.trim();

    if (rawUrl.startsWith('yt://')) {
      final queryOrId = rawUrl.substring(5).trim();
      if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(queryOrId)) {
        return queryOrId;
      }
    }

    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(track.id)) {
      return track.id;
    }

    final query = '${track.artist} ${track.title}'.trim();
    try {
      final results = await _client.search
          .search(query, filter: TypeFilters.video)
          .timeout(const Duration(seconds: 15))
          .then((v) => v.toList());
      if (results.isNotEmpty) {
        final targetTitle = track.title.toLowerCase().trim();

        bool isPureAudio(Video v) {
          final titleLower = v.title.toLowerCase();
          final isVideoClip = titleLower.contains('official music video') ||
              titleLower.contains('official video') ||
              titleLower.contains('music video') ||
              titleLower.contains('clip officiel') ||
              titleLower.contains('short film');
          final isTopic = v.author.toLowerCase().endsWith('- topic') || v.author.toLowerCase().contains('topic');
          final isAudioTagged = titleLower.contains('official audio') || titleLower.contains('(audio)') || titleLower.contains('[audio]');
          return (isTopic || isAudioTagged || !isVideoClip);
        }

        // 1. Strict priority: Title match + Duration +-3s + Explicit match + Pure Audio / Topic (No Clip)
        for (final v in results) {
          final vTitle = v.title.toLowerCase();
          final vDur = v.duration?.inSeconds ?? 0;
          final isTitleMatch = vTitle.contains(targetTitle);
          final isDurationMatch = track.duration > 0 && vDur > 0 && (vDur - track.duration).abs() <= 3;
          final isExplicitMatch = YtUtils.matchesExplicitRequirement(v.title, track.isExplicit);

          if (isTitleMatch && isDurationMatch && isExplicitMatch && isPureAudio(v)) {
            return v.id.value;
          }
        }

        // 2. Secondary: Title match + Duration +-3s + Explicit match
        for (final v in results) {
          final vTitle = v.title.toLowerCase();
          final vDur = v.duration?.inSeconds ?? 0;
          final isTitleMatch = vTitle.contains(targetTitle);
          final isDurationMatch = track.duration > 0 && vDur > 0 && (vDur - track.duration).abs() <= 3;
          final isExplicitMatch = YtUtils.matchesExplicitRequirement(v.title, track.isExplicit);

          if (isTitleMatch && isDurationMatch && isExplicitMatch) {
            return v.id.value;
          }
        }

        // 3. Tertiary: Title match + Pure Audio / Topic
        for (final v in results) {
          final vTitle = v.title.toLowerCase();
          if (vTitle.contains(targetTitle) && YtUtils.matchesExplicitRequirement(v.title, track.isExplicit) && isPureAudio(v)) {
            return v.id.value;
          }
        }

        // 4. Quaternary: Title match
        for (final v in results) {
          final vTitle = v.title.toLowerCase();
          if (vTitle.contains(targetTitle)) {
            return v.id.value;
          }
        }

        return results.first.id.value;
      }
    } on TimeoutException {
      throw const NetworkTimeoutException();
    } on SocketException catch (e) {
      throw NetworkUnavailableException(e.message);
    } on http.ClientException catch (e) {
      throw NetworkUnavailableException(e.message);
    } catch (e) {
      if (kDebugMode) debugPrint('[StreamResolver] resolveVideoId search error: $e');
      if (e is NetworkException) rethrow;
    }

    return null;
  }

  /// Récupère le meilleur flux audio YouTube compatible AVPlayer Apple & Android (M4A/MP4/AAC en priorité)
  Future<StreamInfo?> getAudioStreamInfo(String videoId) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(videoId)) {
      if (kDebugMode) debugPrint('[StreamResolver] Identifiant vidéo invalide: "$videoId"');
      return null;
    }
    
    // 1. TENTATIVE CLIENT ANDROID (Ultra-rapide ~250ms, sans rate-limit watch page)
    try {
      final manifest = await _client.videos.streamsClient.getManifest(
        videoId,
        ytClients: [
          YoutubeApiClient.android,
        ],
        requireWatchPage: false,
      ).timeout(const Duration(seconds: 15));
      
      final selected = _selectPlatformAudioStream(manifest, safeMode: false);
      if (selected != null) {
        if (kDebugMode) debugPrint('[StreamResolver] 🎵 Flux sélectionné: ${selected.bitrate.kiloBitsPerSecond.round()} kbps | Tag: ${selected.tag}');
        return selected;
      }
    } catch (_) {
      // Échec silencieux, passage au plan B
    }

    // 2. PLAN B (Multi-clients de secours)
    try {
      final manifest = await _client.videos.streamsClient.getManifest(
        videoId,
        ytClients: [
          YoutubeApiClient.android,
          YoutubeApiClient.ios,
          YoutubeApiClient.androidVr,
        ],
        requireWatchPage: false,
      ).timeout(const Duration(seconds: 15));
      
      final selected = _selectPlatformAudioStream(manifest, safeMode: true);
      if (selected != null) {
        if (kDebugMode) debugPrint('[StreamResolver] 🛡️ Flux Anti-Blocage sélectionné: ${selected.bitrate.kiloBitsPerSecond.round()} kbps | Tag: ${selected.tag}');
        return selected;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[StreamResolver] ❌ Échec API de secours pour $videoId: $e');
    }

    return null;
  }

  /// Récupère l'URL brute du flux audio
  Future<String?> getAudioStreamUrl(String videoId) async {
    final cached = _resolvedStreamUrls[videoId];
    final cachedAt = _resolvedStreamTimes[videoId];
    if (cached != null && cachedAt != null && DateTime.now().difference(cachedAt) < _streamUrlTtl) {
      return cached;
    }

    final inFlight = _resolvedInFlight[videoId];
    if (inFlight != null) {
      try {
        return await inFlight;
      } catch (_) {
        return null;
      }
    }

    final future = _resolveAudioStreamUrl(videoId);
    _resolvedInFlight[videoId] = future;
    try {
      return await future;
    } finally {
      _resolvedInFlight.remove(videoId);
    }
  }

  Future<String?> _resolveAudioStreamUrl(String videoId) async {
    final streamInfo = await getAudioStreamInfo(videoId);
    if (streamInfo != null) {
      final url = streamInfo.url.toString();
      if (isSafeStreamUrl(url)) {
        _cacheStreamUrl(videoId, url);
        return url;
      }
    }

    return null;
  }

  void _cacheStreamUrl(String videoId, String url) {
    if (_resolvedStreamUrls.length >= _streamUrlCacheMax) {
      final oldestKey = _resolvedStreamUrls.keys.first;
      _resolvedStreamUrls.remove(oldestKey);
      _resolvedStreamTimes.remove(oldestKey);
    }
    final now = DateTime.now();
    _resolvedStreamUrls[videoId] = url;
    _resolvedStreamTimes[videoId] = now;
  }

  /// Checks if an audio file for this track already exists on disk in the downloads directory
  Future<String?> findExistingDownloadedFile(Track track, {String? videoId}) async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final targetDir = Directory(p.join(supportDir.path, 'downloads'));
      if (!await targetDir.exists()) return null;

      final safeArtist = boundedNamePart(track.artist);
      final safeTitle = boundedNamePart(track.title);
      final rawIdTag = (videoId != null && videoId.isNotEmpty)
          ? videoId
          : (track.id.isNotEmpty ? track.id : 'unknown');
      final idTag = boundedNamePart(rawIdTag);

      for (final candidateExt in ['m4a', 'mp3', 'opus', 'webm', 'aac', 'mp4']) {
        final candidatePath = p.join(targetDir.path, '${safeArtist}_${safeTitle}_$idTag.$candidateExt');
        if (!p.isWithin(targetDir.path, candidatePath)) continue;
        final candidate = File(candidatePath);
        if (await candidate.exists() && await candidate.length() > 0) {
          return candidate.path;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Résout une source audio directement compatible et sécurisée pour just_audio
  Future<AudioSource?> resolveAudioSource(
    Track track, {
    dynamic tag,
    void Function(int bitrate)? onBitrateResolved,
  }) async {
    // 1. Priorité absolue au fichier local téléchargé (0ms, 100% hors-ligne)
    if (track.isDownloaded && track.localFilePath != null) {
      final cleanPath = track.localFilePath!.startsWith('file://')
          ? track.localFilePath!.replaceFirst('file://', '')
          : track.localFilePath!;
      final file = File(cleanPath);
      if (file.existsSync() && file.lengthSync() > 0) {
        if (kDebugMode) debugPrint('[StreamResolver] ⚡ Fichier local DIRECT (0ms): $cleanPath');
        if (track.bitrate > 0) onBitrateResolved?.call(track.bitrate);
        return AudioSource.file(cleanPath, tag: tag);
      } else {
        if (kDebugMode) debugPrint('[StreamResolver] ⚠️ Fichier local introuvable au chemin direct: $cleanPath');
      }
    }

    final localDiskFile = await findExistingDownloadedFile(track);
    if (localDiskFile != null) {
      if (kDebugMode) debugPrint('[StreamResolver] ⚡ Fichier local trouvé sur disque: $localDiskFile');
      if (track.bitrate > 0) onBitrateResolved?.call(track.bitrate);
      return AudioSource.file(localDiskFile, tag: tag);
    }

    final rawUrl = track.audioUrl.trim();
    if (rawUrl.startsWith('/') || rawUrl.startsWith('file://')) {
      final cleanPath = rawUrl.startsWith('file://') ? rawUrl.replaceFirst('file://', '') : rawUrl;
      final file = File(cleanPath);
      if (file.existsSync() && file.lengthSync() > 0) {
        if (track.bitrate > 0) onBitrateResolved?.call(track.bitrate);
        return AudioSource.file(cleanPath, tag: tag);
      }
    }

    // 2. Flux HTTP direct standard (ex: podcast, mp3 classique non-YouTube)
    if ((rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) && !rawUrl.contains('googlevideo.com')) {
      if (isSafeStreamUrl(rawUrl)) {
        if (track.bitrate > 0) onBitrateResolved?.call(track.bitrate);
        return AudioSource.uri(Uri.parse(rawUrl), tag: tag);
      }
    }

    // 3. Résolution YouTube
    final videoId = await resolveVideoId(track);
    if (videoId != null && videoId.isNotEmpty) {
      final localWithId = await findExistingDownloadedFile(track, videoId: videoId);
      if (localWithId != null) {
        if (kDebugMode) debugPrint('[StreamResolver] ⚡ Fichier local trouvé avec videoId: $localWithId');
        if (track.bitrate > 0) onBitrateResolved?.call(track.bitrate);
        return AudioSource.file(localWithId, tag: tag);
      }

      final source = await _resolveStreamForVideoId(
        videoId,
        tag: tag,
        onBitrateResolved: onBitrateResolved,
      );
      if (source != null) return source;

      if (kDebugMode) {
        debugPrint('[StreamResolver] ❌ Impossible de résoudre le flux natif pour "${track.title}" par "${track.artist}" (vidéo $videoId inaccessibles).');
      }
    }

    return null;
  }

  /// Résout une URL directement lisible par le lecteur audio
  Future<String> resolvePlayableAudioUrl(Track track) async {
    // 1. Priorité absolue au fichier téléchargé local (zéro latence réseau, 100% hors-ligne)
    if (track.isDownloaded && track.localFilePath != null) {
      final file = File(track.localFilePath!);
      if (file.existsSync()) {
        return file.path;
      }
    }

    final rawUrl = track.audioUrl.trim();

    if (rawUrl.startsWith('/') || rawUrl.startsWith('file://')) {
      return rawUrl;
    }

    if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
      return isSafeStreamUrl(rawUrl) ? rawUrl : '';
    }

    final videoId = await resolveVideoId(track);
    if (videoId != null && videoId.isNotEmpty) {
      final streamUrl = await getAudioStreamUrl(videoId);
      if (streamUrl != null && streamUrl.isNotEmpty) {
        return streamUrl;
      }
    }

    // Si la résolution a échoué (ex: hors-ligne, rate-limit ou piste mock), renvoyer vide
    // pour éviter d'envoyer un schéma invalide type "yt://..." au lecteur natif AVPlayer
    return '';
  }

  /// Résout le flux audio d'un identifiant vidéo spécifique avec vérification de lecture et fallback Piped
  Future<AudioSource?> _resolveStreamForVideoId(
    String videoId, {
    dynamic tag,
    void Function(int bitrate)? onBitrateResolved,
  }) async {
    final streamInfo = await getAudioStreamInfo(videoId);
    if (streamInfo != null) {
      final urlStr = streamInfo.url.toString();
      final isDirectFastStream = urlStr.contains('ratebypass=yes') || urlStr.contains('.m3u8');

      // Les flux progressifs (ratebypass=yes) ou HLS (.m3u8) sont directement
      // consommables par ExoPlayer/AVPlayer sans sonde HTTP bloquante préalable.
      if (isDirectFastStream) {
        final bitrateKbps = streamInfo.bitrate.kiloBitsPerSecond.round();
        if (bitrateKbps > 0) {
          onBitrateResolved?.call(bitrateKbps);
        }
        return AudioSource.uri(
          Uri.parse(urlStr),
          tag: tag,
        );
      }

      bool isPlayable = true;
      try {
        final probeOffset = math.min(512 * 1024, streamInfo.size.totalBytes ~/ 2);
        final probeReq = http.Request('GET', streamInfo.url)
          ..followRedirects = true
          ..headers['Range'] = 'bytes=$probeOffset-${probeOffset + 1000}'
          ..headers['User-Agent'] = BrowserHttpClient.userAgentFor(streamInfo.url)
          ..headers['Accept'] = '*/*';
        final probeRes = await _browserClient.send(probeReq).timeout(const Duration(seconds: 15));
        if (probeRes.statusCode != 200 && probeRes.statusCode != 206) {
          isPlayable = false;
        }
        await probeRes.stream.drain<void>().catchError((_) {});
      } catch (_) {
        isPlayable = false;
      }

      if (isPlayable) {
        final bitrateKbps = streamInfo.bitrate.kiloBitsPerSecond.round();
        if (bitrateKbps > 0) {
          onBitrateResolved?.call(bitrateKbps);
        }
        return YouTubeAudioSource(
          streamInfo: streamInfo,
          httpClient: _browserClient,
          tag: tag,
        );
      } else {
        _resolvedStreamUrls.remove(videoId);
        _resolvedStreamTimes.remove(videoId);
        if (kDebugMode) {
          debugPrint('[StreamResolver] Flux YouTube natif inaccessible ou 403 sur probe pour $videoId.');
        }
      }
    }

    return null;
  }


  /// Télécharge un flux audio pour un morceau vers le stockage local.
  /// Écrit de façon atomique (fichier temporaire + renommage), vérifie le type
  /// de contenu et la taille réelle, ferme toujours le sink, supprime le
  /// temporaire en cas d'échec, borne la longueur des noms, déduplique les
  /// téléchargements du même morceau et limite la concurrence globale.
  Future<String?> downloadAudioStream(
    Track track, {
    String? directStreamUrl,
    void Function(double progress)? onProgress,
    void Function(int bitrate)? onBitrateResolved,
    @visibleForTesting Directory? downloadsDir,
  }) async {
    if (!_activeTrackDownloads.add(track.id)) {
      if (kDebugMode) debugPrint('[StreamResolver] Téléchargement déjà en cours pour "${track.title}" — ignoré.');
      return null;
    }
    try {
      await _acquireDownloadSlot();
      try {
        return await _downloadAudioStream(
          track,
          directStreamUrl: directStreamUrl,
          onProgress: onProgress,
          onBitrateResolved: onBitrateResolved,
          downloadsDir: downloadsDir,
        );
      } catch (e) {
        if (kDebugMode) debugPrint('[StreamResolver] Download error: $e');
        return null;
      } finally {
        _releaseDownloadSlot();
      }
    } finally {
      _activeTrackDownloads.remove(track.id);
    }
  }

  Future<String?> _downloadAudioStream(
    Track track, {
    String? directStreamUrl,
    void Function(double progress)? onProgress,
    void Function(int bitrate)? onBitrateResolved,
    Directory? downloadsDir,
  }) async {
    const maxBytes = _maxDownloadBytes;
    File? tmpFile;
    IOSink? sink;
    try {
      final Directory targetDir;
      if (downloadsDir != null) {
        targetDir = downloadsDir;
      } else {
        final supportDir = await getApplicationSupportDirectory();
        targetDir = Directory(p.join(supportDir.path, 'downloads'));
      }
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      await _pruneStaleTempFiles(targetDir);

      final safeArtist = boundedNamePart(track.artist);
      final safeTitle = boundedNamePart(track.title);
      final videoId = await resolveVideoId(track);
      final rawIdTag = (videoId != null && videoId.isNotEmpty)
          ? videoId
          : (track.id.isNotEmpty ? track.id : 'unknown');
      final idTag = boundedNamePart(rawIdTag);

      // Si le fichier audio existe déjà sur le disque, on retourne immédiatement son chemin
      for (final candidateExt in ['m4a', 'mp3', 'opus', 'webm', 'aac', 'mp4']) {
        final candidatePath = p.join(targetDir.path, '${safeArtist}_${safeTitle}_$idTag.$candidateExt');
        if (!p.isWithin(targetDir.path, candidatePath)) continue;
        final existingCandidate = File(candidatePath);
        if (await existingCandidate.exists() && await existingCandidate.length() > 0) {
          if (kDebugMode) debugPrint('[StreamResolver] Fichier final déjà présent: ${existingCandidate.path}');
          onProgress?.call(1.0);
          return existingCandidate.path;
        }
      }

      // Fichier temporaire unique (Atomicité) — jamais écrit directement dans
      // le fichier final pour éviter les fichiers partiels "téléchargés".
      tmpFile = File(p.join(
        targetDir.path,
        '._tmp_${safeArtist}_${safeTitle}_$idTag.${DateTime.now().microsecondsSinceEpoch}.partial',
      ));
      sink = tmpFile.openWrite();
      int receivedBytes = 0;
      int declaredBytes = 0;

      if (directStreamUrl != null && isSafeStreamUrl(directStreamUrl)) {
        final directUri = Uri.parse(directStreamUrl);
        final res = await NetworkGuard.getWithRedirects(
          client: _browserClient,
          uri: directUri,
          headers: {
            'Range': 'bytes=0-',
            'User-Agent': BrowserHttpClient.userAgentFor(directUri),
          },
          validate: UrlSecurityPolicy.validatePublicDestination,
          timeout: const Duration(seconds: 10),
        );
        if (res.statusCode != 200 && res.statusCode != 206) return null;
        final contentType = res.headers['content-type'] ?? '';
        if (contentType.isNotEmpty && !isAllowedAudioContentType(contentType)) return null;
        declaredBytes = res.contentLength ?? 0;
        if (declaredBytes > maxBytes) return null;
        await for (final chunk in res.stream.timeout(const Duration(seconds: 30))) {
          receivedBytes += chunk.length;
          if (receivedBytes > maxBytes) {
            throw const DownloadException('Téléchargement interrompu : taille maximale dépassée.');
          }
          sink.add(chunk);
          if (declaredBytes > 0 && onProgress != null) {
            onProgress((receivedBytes / declaredBytes).clamp(0.0, 1.0));
          }
        }
      } else {
        if (videoId == null) return null;
        Stream<List<int>>? audioByteStream;

        try {
          final manifest = await _client.videos.streamsClient.getManifest(
            videoId,
            ytClients: [
              YoutubeApiClient.android,
            ],
            requireWatchPage: false,
          ).timeout(const Duration(seconds: 15));
          final studioAudio = _selectStudioAudioStream(manifest);
          if (studioAudio != null) {
            declaredBytes = studioAudio.size.totalBytes;
            final kbps = studioAudio.bitrate.kiloBitsPerSecond.round();
            if (kbps > 0) {
              onBitrateResolved?.call(kbps);
              unawaited(DatabaseService.instance.updateTrackBitrate(track.id, kbps));
            }
            if (kDebugMode) {
              debugPrint('[StreamResolver] 📥 Téléchargement flux studio: ${studioAudio.container.name} | Bitrate: $kbps kbps | Tag: ${studioAudio.tag}');
            }
            audioByteStream = _client.videos.streamsClient.get(studioAudio);
          } else {
            if (kDebugMode) {
              debugPrint('[StreamResolver] ❌ Aucun flux audio studio trouvé pour $videoId');
            }
          }
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
            debugPrint('[StreamResolver] ❌ ERREUR BRUTE API TÉLÉCHARGEMENT pour $videoId:');
            debugPrint('$e');
            debugPrint('Type: ${e.runtimeType}');
            debugPrint('Stack Trace:\n$st');
            debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          }
        }
        if (audioByteStream != null) {
          if (declaredBytes > maxBytes) return null;
          await for (final List<int> chunk in audioByteStream.timeout(const Duration(seconds: 45))) {
            receivedBytes += chunk.length;
            if (receivedBytes > maxBytes) {
              throw const DownloadException('Téléchargement interrompu : taille maximale dépassée.');
            }
            sink.add(chunk);
            if (declaredBytes > 0 && onProgress != null) {
              onProgress((receivedBytes / declaredBytes).clamp(0.0, 1.0));
            }
          }
        } else {
          final streamUrl = await getAudioStreamUrl(videoId);
          if (streamUrl == null || !isSafeStreamUrl(streamUrl)) return null;

          final streamUri = Uri.parse(streamUrl);
          final res = await NetworkGuard.getWithRedirects(
            client: _browserClient,
            uri: streamUri,
            headers: {
              'Range': 'bytes=0-',
              'User-Agent': BrowserHttpClient.userAgentFor(streamUri),
            },
            validate: UrlSecurityPolicy.validatePublicDestination,
            timeout: const Duration(seconds: 15),
          );
          if (res.statusCode != 200 && res.statusCode != 206) return null;
          declaredBytes = res.contentLength ?? 0;
          if (declaredBytes > maxBytes) return null;
          await for (final List<int> chunk in res.stream.timeout(const Duration(seconds: 30))) {
            receivedBytes += chunk.length;
            if (receivedBytes > maxBytes) {
              throw const DownloadException('Téléchargement interrompu : taille maximale dépassée.');
            }
            sink.add(chunk);
            if (declaredBytes > 0 && onProgress != null) {
              onProgress((receivedBytes / declaredBytes).clamp(0.0, 1.0));
            }
          }
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (receivedBytes == 0) return null;
      if (declaredBytes > 0 && receivedBytes != declaredBytes) {
        throw const DownloadException('Téléchargement incomplet (taille réelle ≠ taille annoncée).');
      }

      // Vérifier le conteneur réel (magic bytes) avant de choisir l'extension.
      final header = await _readHeaderBytes(tmpFile);
      final detectedExt = detectExtensionFromHeader(header);
      if (detectedExt == null) {
        throw const DownloadException('Conteneur audio non reconnu.');
      }
      final ext = detectedExt;

      final targetPath = p.join(targetDir.path, '${safeArtist}_${safeTitle}_$idTag.$ext');
      if (!p.isWithin(targetDir.path, targetPath)) {
        throw const DownloadException('Chemin de destination invalide.');
      }
      final targetFile = File(targetPath);
      if (await targetFile.exists() && await targetFile.length() > 0) {
        if (kDebugMode) debugPrint('[StreamResolver] Fichier final déjà présent: ${targetFile.path}');
        onProgress?.call(1.0);
        return targetFile.path;
      }
      await tmpFile.rename(targetFile.path);
      tmpFile = null;
      onProgress?.call(1.0);
      return targetFile.path;
    } finally {
      // Fermeture garantie du sink + suppression du temporaire en cas d'échec.
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      if (tmpFile != null) {
        try {
          if (await tmpFile.exists()) await tmpFile.delete();
        } catch (_) {}
      }
    }
  }

  /// Lit les premiers octets d'un fichier pour en détecter le format.
  static Future<List<int>> _readHeaderBytes(File file) async {
    try {
      final raf = await file.open();
      try {
        return await raf.read(16);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return const [];
    }
  }

  /// Devine l'extension depuis les magic bytes audio (MP4/M4A, WebM/Matroska,
  /// Ogg, MP3).
  @visibleForTesting
  static String? detectExtensionFromHeader(List<int> header) {
    if (header.length >= 4) {
      // MP4 / M4A : octets 4-7 == "ftyp".
      if (header.length >= 8 &&
          header[4] == 0x66 && header[5] == 0x74 &&
          header[6] == 0x79 && header[7] == 0x70) {
        return 'm4a';
      }
      // WebM / Matroska : 1A 45 DF A3.
      if (header[0] == 0x1A && header[1] == 0x45 &&
          header[2] == 0xDF && header[3] == 0xA3) {
        return 'webm';
      }
      // Ogg : "OggS".
      if (header[0] == 0x4F && header[1] == 0x67 &&
          header[2] == 0x67 && header[3] == 0x53) {
        return 'ogg';
      }
      // MP3 : 0xFF 0xFB.
      if (header[0] == 0xFF && header[1] == 0xFB) {
        return 'mp3';
      }
    }
    return null;
  }

  /// Nettoie et borne une portion de nom de fichier (bloque aussi les séquences `..` et caractères de contrôle).
  @visibleForTesting
  static String boundedNamePart(String value) {
    var clean = value
        .replaceAll(RegExp(r'[\x00-\x1F\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\.{2,}'), '_')
        .trim();
    clean = clean.replaceAll(RegExp(r'^\.+|\.+$'), '').trim();
    if (clean.isEmpty) clean = 'track';
    if (clean.length > _maxNamePartLength) {
      clean = clean.substring(0, _maxNamePartLength);
    }
    return clean;
  }

  /// Supprime les fichiers temporaires `.partial` obsolètes (non critiques).
  static Future<void> _pruneStaleTempFiles(Directory dir) async {
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File && p.basename(entity.path).startsWith('._tmp_')) {
          final stat = await entity.stat();
          if (DateTime.now().difference(stat.modified) > const Duration(days: 1)) {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
  }

  @visibleForTesting
  static bool isAllowedAudioContentType(String contentType) {
    final t = contentType.toLowerCase().split(';').first.trim();
    return t.startsWith('audio/') ||
        t.startsWith('video/') ||
        t == 'application/octet-stream' ||
        t == 'application/ogg' ||
        t == 'application/x-ogg';
  }
}
