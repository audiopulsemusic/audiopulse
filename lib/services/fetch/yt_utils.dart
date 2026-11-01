import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// HTTP Client with proper platform User-Agent simulation for YouTube InnerTube/CDN
class BrowserHttpClient extends http.BaseClient {
  BrowserHttpClient({http.Client? inner}) : _inner = inner ?? http.Client();

  final http.Client _inner;

  static bool _isYouTubeHost(String host) {
    final h = host.toLowerCase();
    return h == 'youtube.com' || h.endsWith('.youtube.com');
  }

  /// Maps YouTube's `c` client query parameter to the matching transport
  /// profile. The parameter belongs to the signed stream URL and can be
  /// absent; desktop Chrome remains the safe default in that case.
  @visibleForTesting
  static String clientProfile(Uri uri) {
    final value = (uri.queryParameters['c'] ?? '').toUpperCase();
    if (value.contains('ANDROID')) return 'android';
    if (value == 'IOS' || value.contains('IPHONE')) return 'ios';
    if (value == 'TV' || value.contains('TVHTML')) return 'tv';
    return 'desktop';
  }

  static String userAgentFor(Uri uri) {
    switch (clientProfile(uri)) {
      case 'android':
        return 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36';
      case 'ios':
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
      case 'tv':
        return 'Mozilla/5.0 (SMART-TV; Linux; Tizen 6.0) AppleWebKit/537.36 '
            '(KHTML, like Gecko) 76.0.3809.146 TV Safari/537.36';
      case 'desktop':
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
            'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';
    }
    return 'Mozilla/5.0';
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final profile = clientProfile(request.url);
    request.headers['User-Agent'] = userAgentFor(request.url);
    request.headers.putIfAbsent('Accept-Language', () => 'fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7');
    request.headers.putIfAbsent('Accept', () => '*/*');
    if (profile == 'desktop') {
      request.headers['sec-ch-ua'] = '"Chromium";v="122", "Google Chrome";v="122", "Not-A.Brand";v="99"';
      request.headers['sec-ch-ua-mobile'] = '?0';
      request.headers['sec-ch-ua-platform'] = '"macOS"';
      request.headers.putIfAbsent('sec-fetch-dest', () => 'empty');
      request.headers.putIfAbsent('sec-fetch-mode', () => 'cors');
      request.headers.putIfAbsent(
        'sec-fetch-site',
        () => _isYouTubeHost(request.url.host) ? 'same-origin' : 'cross-site',
      );
    } else {
      request.headers.remove('sec-ch-ua');
      request.headers.remove('sec-ch-ua-mobile');
      request.headers.remove('sec-ch-ua-platform');
      request.headers.remove('sec-fetch-dest');
      request.headers.remove('sec-fetch-mode');
      request.headers.remove('sec-fetch-site');
    }

    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

/// Helper utilities for title parsing, thumbnail extraction, and color generation
class YtUtils {
  /// Clean title by removing "Artist - ", "Artist – ", "Artist : ", "Artist | " prefixes
  /// and redundant suffixes like "[ALBUM]", "(Full Album)", "(Full Mixtape)", etc.
  static String cleanTitle(String rawTitle, {String artist = ''}) {
    String s = rawTitle.trim();
    if (s.isEmpty) return s;

    // 1. Strip "Artist - " or "Artist – " or "Artist — " or "Artist : " or "Artist | "
    for (final sep in [' - ', ' – ', ' — ', ' : ', ' | ']) {
      if (s.contains(sep)) {
        final parts = s.split(sep);
        final prefix = parts[0].trim();
        if (artist.isNotEmpty &&
            (prefix.toLowerCase() == artist.toLowerCase() ||
             prefix.toLowerCase().contains(artist.toLowerCase()) ||
             artist.toLowerCase().contains(prefix.toLowerCase()))) {
          s = parts.sublist(1).join(sep).trim();
          break;
        } else if (prefix.isNotEmpty && parts.length >= 2) {
          s = parts.sublist(1).join(sep).trim();
          break;
        }
      }
    }

    // 2. Strip "Artist ( Title" or "Artist [ Title"
    if (artist.isNotEmpty) {
      final artistRegex = RegExp('^${RegExp.escape(artist)}\\s*[\\(\\[]\\s*', caseSensitive: false);
      if (artistRegex.hasMatch(s)) {
        s = s.replaceFirst(artistRegex, '').replaceAll(RegExp(r'[\)\]]\s*$'), '').trim();
      }
    }

    // 3. Strip trailing tags like [ALBUM], (Full Album), (Full Mixtape)
    s = s
        .replaceAll(RegExp(r'\s*[\(\[](full\s+album|full\s+mixtape|official\s+album|album)[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+[-–—]\s*$'), '')
        .trim();

    return s.isNotEmpty ? s : rawTitle.trim();
  }

  /// Extract clean title and artist by removing the "TEXT - " prefix only, keeping the rest intact
  static Map<String, String> parseCleanTitleAndArtist(String rawTitle, String author) {
    String cleanTitle = rawTitle.trim();
    String cleanArtist = author.replaceAll(' - Topic', '').replaceAll(' Official', '').replaceAll(' VEVO', '').trim();

    if (cleanTitle.contains(' - ')) {
      final parts = cleanTitle.split(' - ');
      final potentialArtist = parts[0].trim();
      final potentialTitle = parts.sublist(1).join(' - ').trim();

      if (potentialArtist.isNotEmpty && potentialTitle.isNotEmpty) {
        cleanArtist = potentialArtist;
        cleanTitle = potentialTitle;
      }
    }

    return {
      'artist': cleanArtist.isNotEmpty ? cleanArtist : author.trim(),
      'title': cleanTitle.isNotEmpty ? cleanTitle : rawTitle.trim(),
    };
  }

  /// Parse duration strings like "3:45" or "1:15:30" into total seconds
  static int parseDurationString(String durationStr) {
    try {
      final parts = durationStr.trim().split(':');
      if (parts.length == 2) {
        return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
      } else if (parts.length == 3) {
        return (int.tryParse(parts[0]) ?? 0) * 3600 +
            (int.tryParse(parts[1]) ?? 0) * 60 +
            (int.tryParse(parts[2]) ?? 0);
      }
    } catch (_) {}
    return 0;
  }

  /// Extract official duration in seconds from any InnerTube renderer object
  static int extractDurationFromRenderer(Map<String, dynamic> renderer) {
    // 1. Check fixedColumns
    final fixedCols = renderer['fixedColumns'] as List<dynamic>?;
    if (fixedCols != null) {
      for (final col in fixedCols) {
        final runs = col?['musicResponsiveListItemFixedColumnRenderer']?['text']?['runs'] as List<dynamic>?;
        if (runs != null) {
          for (final r in runs) {
            final text = (r['text'] as String?)?.trim() ?? '';
            final d = parseDurationString(text);
            if (d > 0) return d;
          }
        }
      }
    }

    // 2. Check lengthText
    final lengthText = renderer['lengthText']?['runs']?[0]?['text'] as String? ??
        renderer['lengthText']?['simpleText'] as String?;
    if (lengthText != null) {
      final d = parseDurationString(lengthText.trim());
      if (d > 0) return d;
    }

    // 3. Check all runs in flexColumns
    final flexCols = renderer['flexColumns'] as List<dynamic>?;
    if (flexCols != null) {
      for (final col in flexCols) {
        final runs = col?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List<dynamic>?;
        if (runs != null) {
          for (final r in runs) {
            final text = (r['text'] as String?)?.trim() ?? '';
            if (RegExp(r'^\d+:\d{2}(:\d{2})?$').hasMatch(text)) {
              final d = parseDurationString(text);
              if (d > 0) return d;
            }
          }
        }
      }
    }

    return 0;
  }

  /// Extract explicit badge status directly from reliable badges structure
  static bool extractIsExplicitFromRenderer(Map<String, dynamic> renderer) {
    bool hasExplicitBadge(List<dynamic>? badgesList) {
      if (badgesList == null) return false;
      for (final b in badgesList) {
        if (b is Map<String, dynamic>) {
          final iconType = b['musicInlineBadgeRenderer']?['icon']?['iconType'] as String?;
          if (iconType == 'MUSIC_EXPLICIT_BADGE') return true;
          final label = b['musicInlineBadgeRenderer']?['accessibilityData']?['accessibilityData']?['label'] as String?;
          if (label != null && label.toLowerCase().contains('explicit')) return true;
        }
      }
      return false;
    }

    // 1. Check direct badges
    if (hasExplicitBadge(renderer['badges'] as List<dynamic>?)) return true;

    // 2. Check flexColumns[0] badges
    final flexCols = renderer['flexColumns'] as List<dynamic>?;
    if (flexCols != null && flexCols.isNotEmpty) {
      final firstCol = flexCols[0];
      if (firstCol is Map<String, dynamic>) {
        final flexRenderer = firstCol['musicResponsiveListItemFlexColumnRenderer'];
        if (flexRenderer is Map<String, dynamic>) {
          if (hasExplicitBadge(flexRenderer['badges'] as List<dynamic>?)) return true;
        }
      }
    }

    return false;
  }

  /// Verify if candidate video matches explicit requirement (rejects Clean/Radio Edit on Explicit tracks)
  static bool matchesExplicitRequirement(String videoTitle, bool targetExplicit) {
    final lower = videoTitle.toLowerCase();
    final isMarkedClean = lower.contains('clean') ||
        lower.contains('radio edit') ||
        lower.contains('censored') ||
        lower.contains('clean version') ||
        lower.contains('clean edit');

    final isMarkedExplicit = lower.contains('explicit') ||
        lower.contains('uncensored') ||
        lower.contains('dirty') ||
        lower.contains('parental advisory');

    if (targetExplicit) {
      // For explicit track, reject clean / censored versions
      if (isMarkedClean) return false;
      return true;
    } else {
      // For non-explicit track, reject versions explicitly tagged as dirty / explicit
      if (isMarkedExplicit) return false;
      return true;
    }
  }

  /// Get the safest high resolution thumbnail URL available on YouTube
  /// Uses highResUrl (hqdefault.jpg) which is guaranteed to exist (HTTP 200) for all videos.
  /// maxResUrl (maxresdefault.jpg) frequently returns HTTP 404 for non-HD videos.
  static String getBestThumbnail(Video video) {
    if (video.thumbnails.highResUrl.isNotEmpty) {
      return video.thumbnails.highResUrl;
    }
    if (video.thumbnails.mediumResUrl.isNotEmpty) {
      return video.thumbnails.mediumResUrl;
    }
    if (video.thumbnails.standardResUrl.isNotEmpty) {
      return video.thumbnails.standardResUrl;
    }
    return 'https://i.ytimg.com/vi/${video.id.value}/hqdefault.jpg';
  }

  /// Pick an ambient background color based on an ID hash
  static String pickAmbientColor(String id) {
    const colors = [
      '#EC4899',
      '#8B5CF6',
      '#3B82F6',
      '#10B981',
      '#F59E0B',
      '#EF4444',
      '#06B6D4',
      '#A855F7',
    ];
    final hash = id.hashCode.abs();
    return colors[hash % colors.length];
  }

  /// Format view count into human-readable compact notation (e.g. 1.2M)
  static String formatCompactViews(int views) {
    if (views >= 1000000000) return '${(views / 1000000000).toStringAsFixed(1)}B';
    if (views >= 1000000) return '${(views / 1000000).toStringAsFixed(1)}M';
    if (views >= 1000) return '${(views / 1000).toStringAsFixed(1)}k';
    return views.toString();
  }

  /// Deep search for a JSON key across nested structures
  static dynamic findDeepKey(dynamic obj, String targetKey) {
    if (obj is Map<String, dynamic>) {
      if (obj.containsKey(targetKey)) return obj[targetKey];
      for (final val in obj.values) {
        final found = findDeepKey(val, targetKey);
        if (found != null) return found;
      }
    } else if (obj is List) {
      for (final item in obj) {
        final found = findDeepKey(item, targetKey);
        if (found != null) return found;
      }
    }
    return null;
  }
}
