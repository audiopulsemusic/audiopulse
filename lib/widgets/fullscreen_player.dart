import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';
import '../models/track.dart';
import '../theme/app_theme.dart';
import 'app_network_image.dart';
import 'album_playlist_stage.dart';

class FullScreenPlayer extends StatefulWidget {
  const FullScreenPlayer({super.key});

  @override
  State<FullScreenPlayer> createState() => _FullScreenPlayerState();
}

class _FullScreenPlayerState extends State<FullScreenPlayer> {
  final PageController _pageController = PageController(initialPage: 0);
  final Map<String, Color> _paletteCache = {};
  Color? _extractedColor;
  String _lastCoverUrl = '';

  // État local de défilement fluide (zéro-latence à 60/120 FPS)
  bool _isDraggingScrubber = false;
  double _dragProgress = 0.0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _formatTime(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds < 10 ? '0' : ''}$seconds';
  }

  void _extractColor(String coverUrl, Color fallback) {
    if (coverUrl.isEmpty || (coverUrl == _lastCoverUrl && _extractedColor != null)) return;
    _lastCoverUrl = coverUrl;

    if (_paletteCache.containsKey(coverUrl)) {
      setState(() => _extractedColor = _paletteCache[coverUrl]);
      return;
    }

    PaletteGenerator.fromImageProvider(
      NetworkImage(coverUrl),
      size: const Size(60, 60),
      maximumColorCount: 8,
    ).timeout(const Duration(seconds: 2)).then((palette) {
      final color = palette.vibrantColor?.color ??
                    palette.dominantColor?.color ??
                    palette.lightVibrantColor?.color ??
                    palette.mutedColor?.color ??
                    fallback;
      _paletteCache[coverUrl] = color;
      if (mounted) {
        setState(() => _extractedColor = color);
      }
    }).catchError((_) {
      if (mounted) {
        setState(() => _extractedColor = fallback);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioProvider>();
    final track = audio.currentTrack;
    if (!audio.isFullPlayerOpen || track == null) return const SizedBox.shrink();

    final fallbackColor = AppTheme.parseHexColor(track.ambientColor);
    _extractColor(track.coverUrl, fallbackColor);
    final dynamicAccentColor = _extractedColor ?? fallbackColor;

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 860;
    final durationSeconds = audio.duration.inSeconds > 0 ? audio.duration.inSeconds : 1;
    final currentSeconds = audio.currentPosition.inSeconds;
    final progress = _isDraggingScrubber
        ? _dragProgress
        : (currentSeconds / durationSeconds).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Deep Dark Backdrop with Dynamic Blur & Lighting
          Positioned.fill(
            child: Container(
              color: const Color(0xFF04060A),
            ),
          ),

          // Blurred Album Art Aura Background
          Positioned.fill(
            child: Opacity(
              opacity: 0.22,
              child: AppNetworkImage(
                imageUrl: track.coverUrl,
                fit: BoxFit.cover,
              ),
            ),
          ),

          // Ambient Color Nebulas with Dynamic Extracted Tone
          Positioned(
            top: -100,
            left: isDesktop ? 100 : -40,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              width: 450,
              height: 450,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dynamicAccentColor.withValues(alpha: 0.35),
                boxShadow: [
                  BoxShadow(
                    color: dynamicAccentColor.withValues(alpha: 0.45),
                    blurRadius: 180,
                    spreadRadius: 90,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -90,
            right: isDesktop ? 120 : -50,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dynamicAccentColor.withValues(alpha: 0.22),
                boxShadow: [
                  BoxShadow(
                    color: dynamicAccentColor.withValues(alpha: 0.35),
                    blurRadius: 160,
                    spreadRadius: 80,
                  ),
                ],
              ),
            ),
          ),

          // Top Accent Glow line
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 2,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    dynamicAccentColor.withValues(alpha: 0.8),
                    AppTheme.primaryPink.withValues(alpha: 0.8),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Vertical PageView to slide down to album playlist
          PageView(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            onPageChanged: (index) {
              if (index == 1) {
                audio.loadAlbumTracks(track);
              }
            },
            children: [
              // Page 0: Main FullScreen Player Layout
              _buildMainPlayerStage(context, audio, track, dynamicAccentColor, progress, isDesktop),

              // Page 1: Album Playlist & Tracks List (Unified Component)
              AlbumPlaylistStage(
                title: track.album.isNotEmpty ? track.album : track.title,
                artist: track.artist,
                coverUrl: track.coverUrl,
                genre: track.genre,
                ambientColor: dynamicAccentColor,
                closeLabel: 'Glisser vers le bas pour revenir au lecteur',
                onClose: () => _pageController.animateToPage(
                  0,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOutCubic,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 1. Core Player Stage Page
  Widget _buildMainPlayerStage(
    BuildContext context,
    AudioProvider audio,
    Track track,
    Color dynamicAccentColor,
    double progress,
    bool isDesktop,
  ) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Column(
              children: [
                // Top Navigation Bar
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Close button
                      IconButton(
                        onPressed: () => audio.setIsFullPlayerOpen(false),
                        tooltip: 'Réduire le lecteur',
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0x2AFFFFFF),
                          hoverColor: const Color(0x4DFFFFFF),
                          padding: const EdgeInsets.all(10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(color: Color(0x33FFFFFF)),
                          ),
                        ),
                        icon: const Icon(LucideIcons.chevron_down, color: Colors.white, size: 22),
                      ),

                      // Center Album Name
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                track.album.isNotEmpty ? track.album : 'Audio Pulse',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Queue Button
                      IconButton(
                        onPressed: () => audio.setIsQueueOpen(true),
                        tooltip: 'File d’attente',
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0x2AFFFFFF),
                          hoverColor: const Color(0x4DFFFFFF),
                          padding: const EdgeInsets.all(10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(color: Color(0x33FFFFFF)),
                          ),
                        ),
                        icon: const Icon(LucideIcons.list_music, color: Colors.white, size: 20),
                      ),
                    ],
                  ),
                ),

                // Main Stage Area (Circular Scrubber + Artwork + Centered Time + Aligned Title & Artist)
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: _buildLargeArtworkAndHeader(track, dynamicAccentColor, audio, progress),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Unified Bottom Control Dock (Controls + Merged Action Buttons)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xCC0E121A),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: const Color(0x33FFFFFF)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.7),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                      BoxShadow(
                        color: dynamicAccentColor.withValues(alpha: 0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1. Playback Controls Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Left: Shuffle button
                          IconButton(
                            onPressed: () => audio.toggleShuffle(),
                            tooltip: 'Lecture aléatoire',
                            style: IconButton.styleFrom(
                              backgroundColor: audio.isShuffle ? dynamicAccentColor.withValues(alpha: 0.25) : Colors.transparent,
                            ),
                            icon: Icon(
                              LucideIcons.shuffle,
                              size: 19,
                              color: audio.isShuffle ? dynamicAccentColor : AppTheme.textSecondary,
                            ),
                          ),

                          // Center Transport Controls
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Previous
                              IconButton(
                                onPressed: () => audio.playPrevious(),
                                tooltip: 'Morceau précédent',
                                icon: const Icon(
                                  LucideIcons.skip_back,
                                  size: 24,
                                  color: Colors.white,
                                ),
                              ),

                              const SizedBox(width: 14),

                              // Hero Play/Pause Button
                              GestureDetector(
                                onTap: () => audio.togglePlayPause(),
                                child: Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: dynamicAccentColor,
                                    boxShadow: [
                                      BoxShadow(
                                        color: dynamicAccentColor.withValues(alpha: 0.55),
                                        blurRadius: 20,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Icon(
                                      audio.isPlaying ? LucideIcons.pause : LucideIcons.play,
                                      size: 26,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(width: 14),

                              // Next
                              IconButton(
                                onPressed: () => audio.playNext(),
                                tooltip: 'Morceau suivant',
                                icon: const Icon(
                                  LucideIcons.skip_forward,
                                  size: 24,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),

                          // Right: Repeat mode button
                          IconButton(
                            onPressed: () => audio.toggleRepeat(),
                            tooltip: 'Mode répétition',
                            style: IconButton.styleFrom(
                              backgroundColor: audio.repeatMode != 'off' ? dynamicAccentColor.withValues(alpha: 0.25) : Colors.transparent,
                            ),
                            icon: Icon(
                              audio.repeatMode == 'one' ? LucideIcons.repeat_1 : LucideIcons.repeat,
                              size: 19,
                              color: audio.repeatMode != 'off' ? dynamicAccentColor : AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),
                      const Divider(color: Color(0x1AFFFFFF), height: 1),
                      const SizedBox(height: 12),

                      // 2. Merged Actions: [ Afficher l'album ] & [ Téléchargement hors-ligne ]
                      Row(
                        children: [
                          // Afficher l'album
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                audio.loadAlbumTracks(track);
                                _pageController.animateToPage(
                                  1,
                                  duration: const Duration(milliseconds: 380),
                                  curve: Curves.easeInOutCubic,
                                );
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0x1FFFFFFF),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0x2EFFFFFF)),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(LucideIcons.disc, size: 14, color: AppTheme.accentEmerald),
                                    SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        'Afficher l\'album',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Icon(LucideIcons.chevron_down, size: 13, color: AppTheme.textMuted),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 10),

                          // Téléchargement hors-ligne
                          Expanded(
                            child: InkWell(
                              onTap: () => audio.toggleDownload(track.id),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                decoration: BoxDecoration(
                                  color: track.isDownloaded
                                      ? const Color(0x2210B981)
                                      : const Color(0x1FFFFFFF),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: track.isDownloaded
                                        ? AppTheme.accentEmerald
                                        : const Color(0x2EFFFFFF),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      track.isDownloaded ? LucideIcons.circle_check : LucideIcons.download,
                                      size: 14,
                                      color: track.isDownloaded
                                          ? AppTheme.accentEmerald
                                          : AppTheme.textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        track.isDownloaded ? 'Téléchargé' : 'Téléchargement',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: track.isDownloaded
                                              ? AppTheme.accentEmerald
                                              : Colors.white,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }



  double _distanceToCenter(Offset localPosition, double size) {
    final center = Offset(size / 2, size / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _calculateAngleFraction(Offset localPosition, double size) {
    final center = Offset(size / 2, size / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    var angle = math.atan2(dy, dx) + (math.pi / 2);
    if (angle < 0) {
      angle += 2 * math.pi;
    }
    return (angle / (2 * math.pi)).clamp(0.0, 1.0);
  }

  void _onScrubberPanDown(DragDownDetails details, double scrubberSize, double artworkRadius) {
    final distance = _distanceToCenter(details.localPosition, scrubberSize);
    // Uniquement actif sur l'anneau / curseur extérieur (pas sur le disque d'album)
    if (distance >= artworkRadius - 4) {
      _isDraggingScrubber = true;
      _dragProgress = _calculateAngleFraction(details.localPosition, scrubberSize);
      setState(() {});
    } else {
      _isDraggingScrubber = false;
    }
  }

  void _onScrubberPanUpdate(DragUpdateDetails details, double scrubberSize) {
    if (_isDraggingScrubber) {
      _dragProgress = _calculateAngleFraction(details.localPosition, scrubberSize);
      setState(() {});
    }
  }

  void _onScrubberPanEnd(DragEndDetails details, AudioProvider audio) {
    if (_isDraggingScrubber) {
      _isDraggingScrubber = false;
      final totalSeconds = audio.duration.inSeconds;
      if (totalSeconds > 0) {
        final targetSeconds = (_dragProgress * totalSeconds).toInt().clamp(0, totalSeconds);
        audio.seek(Duration(seconds: targetSeconds));
      }
      setState(() {});
    }
  }

  void _onScrubberPanCancel() {
    if (_isDraggingScrubber) {
      _isDraggingScrubber = false;
      setState(() {});
    }
  }

  void _onScrubberTapUp(TapUpDetails details, double scrubberSize, double artworkRadius, AudioProvider audio) {
    final distance = _distanceToCenter(details.localPosition, scrubberSize);
    if (distance < artworkRadius - 4) {
      // Tap sur la photo d'album : Pause / Reprise instantanée
      audio.togglePlayPause();
    } else {
      // Tap sur l'anneau extérieur : changement de position immédiat
      final progress = _calculateAngleFraction(details.localPosition, scrubberSize);
      final totalSeconds = audio.duration.inSeconds;
      if (totalSeconds > 0) {
        final targetSeconds = (progress * totalSeconds).toInt().clamp(0, totalSeconds);
        audio.seek(Duration(seconds: targetSeconds));
      }
    }
  }

  // Large Artwork with Circular Progress Scrubber + Time + Aligned Title & Artist
  Widget _buildLargeArtworkAndHeader(Track track, Color ambientColor, AudioProvider audio, double progress) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final scrubberSize = availableWidth;
        final artworkInnerSize = scrubberSize - 28;
        final artworkRadius = artworkInnerSize / 2;

        final durationSeconds = audio.duration.inSeconds > 0 ? audio.duration.inSeconds : 1;
        final currentSeconds = _isDraggingScrubber
            ? (_dragProgress * durationSeconds).toInt()
            : audio.currentPosition.inSeconds;
        final displayPosition = Duration(seconds: currentSeconds);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 1. Time display (01:23 | 03:40) réactif en direct pendant le glissement
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0x1FFFFFFF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x22FFFFFF)),
              ),
              child: Text(
                '${_formatTime(displayPosition)} | ${_formatTime(audio.duration)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.8,
                  fontFamily: 'monospace',
                ),
              ),
            ),

            const SizedBox(height: 18),

            // 2. Interactive Circular Scrubber surrounding the Artwork (Zone réduite à l'anneau extérieur)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (details) => _onScrubberPanDown(details, scrubberSize, artworkRadius),
              onPanUpdate: (details) => _onScrubberPanUpdate(details, scrubberSize),
              onPanEnd: (details) => _onScrubberPanEnd(details, audio),
              onPanCancel: _onScrubberPanCancel,
              onTapUp: (details) => _onScrubberTapUp(details, scrubberSize, artworkRadius, audio),
              child: SizedBox(
                width: scrubberSize,
                height: scrubberSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Circular Scrubber Canvas (Curseur & Piste)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _CircularScrubberPainter(
                          progress: progress,
                          activeColor: ambientColor,
                          trackColor: const Color(0x2EFFFFFF),
                          strokeWidth: 4.5,
                        ),
                      ),
                    ),

                    // Inner Artwork (Disque de photo d'album cliquable pour Play/Pause)
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        width: artworkInnerSize,
                        height: artworkInnerSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: ambientColor.withValues(alpha: 0.4),
                              blurRadius: 32,
                              spreadRadius: 2,
                              offset: const Offset(0, 8),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.8),
                              blurRadius: 18,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              AppNetworkImage(
                                imageUrl: track.coverUrl,
                                width: artworkInnerSize,
                                height: artworkInnerSize,
                              ),
                              // Subtle gloss overlay
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.white.withValues(alpha: 0.15),
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.3),
                                    ],
                                  ),
                                ),
                              ),
                              // Indicateur discret Play/Pause sur le disque de photo
                              AnimatedOpacity(
                                opacity: audio.isPlaying ? 0.0 : 1.0,
                                duration: const Duration(milliseconds: 200),
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.black.withValues(alpha: 0.5),
                                        border: Border.all(
                                          color: Colors.white.withValues(alpha: 0.35),
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.5),
                                            blurRadius: 16,
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        LucideIcons.play,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 22),

            // 3. Track Title & Artist Name (Left-Aligned with Badges)
            SizedBox(
              width: availableWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      // Badge 1x1 : Source (M pour Music / YT pour YouTube)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: track.source == 'music'
                              ? const Color(0x3306B6D4)
                              : const Color(0x33EF4444),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: track.source == 'music'
                                ? const Color(0x4D06B6D4)
                                : const Color(0x4DEF4444),
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          track.source == 'music' ? 'M' : 'YT',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: track.source == 'music'
                                ? const Color(0xFF22D3EE)
                                : const Color(0xFFF87171),
                            height: 1.0,
                          ),
                        ),
                      ),
                      // Badge 1x1 : Explicite (E)
                      if (track.isExplicit) ...[
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0x33EF4444),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.6)),
                          ),
                          child: const Text(
                            'E',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Colors.redAccent,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ],
                      Flexible(
                        child: Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.left,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CircularScrubberPainter extends CustomPainter {
  final double progress;
  final Color activeColor;
  final Color trackColor;
  final double strokeWidth;

  _CircularScrubberPainter({
    required this.progress,
    required this.activeColor,
    required this.trackColor,
    this.strokeWidth = 4.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - (strokeWidth / 2);

    // Inactive track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress > 0) {
      const startAngle = -math.pi / 2;
      final sweepAngle = (progress * 2 * math.pi).clamp(0.0, 2 * math.pi);

      // Active arc glow
      final glowPaint = Paint()
        ..color = activeColor.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 4.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        glowPaint,
      );

      // Active arc
      final activePaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        activePaint,
      );

      // Knob thumb at current position
      final knobAngle = startAngle + sweepAngle;
      final knobCenter = Offset(
        center.dx + radius * math.cos(knobAngle),
        center.dy + radius * math.sin(knobAngle),
      );

      final knobShadow = Paint()
        ..color = activeColor.withValues(alpha: 0.9)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);
      canvas.drawCircle(knobCenter, 7.0, knobShadow);

      final knobPaint = Paint()..color = Colors.white;
      canvas.drawCircle(knobCenter, 5.5, knobPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CircularScrubberPainter oldDelegate) {
    return oldDelegate.progress != progress ||
           oldDelegate.activeColor != activeColor ||
           oldDelegate.trackColor != trackColor;
  }
}
