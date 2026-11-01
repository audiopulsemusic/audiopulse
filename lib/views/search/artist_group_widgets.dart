import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import '../../models/album.dart';
import '../../models/artist.dart';
import '../../models/track.dart';
import '../../providers/audio_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_network_image.dart';
import '../../widgets/track_tile.dart';
import 'search_skeletons.dart';

/// Renders an artist's grouped search block (Header, Discography, and Top Tracks)
class ArtistGroupBlock extends StatelessWidget {
  final String artistName;
  final String artistId;
  final List<Track> tracks;
  final String searchQuery;
  final Album? matchedAlbum;
  final Album? matchedPlaylist;
  final String artistAvatarUrl;
  final List<Album> artistReleases;
  final List<Album> artistPlaylists;
  final bool isResolvingTarget;
  final bool isResolvingAlbums;
  final ValueChanged<Album> onAlbumTap;
  final bool initialShowPlaylists;

  const ArtistGroupBlock({
    super.key,
    required this.artistName,
    required this.artistId,
    required this.tracks,
    this.searchQuery = '',
    this.matchedAlbum,
    this.matchedPlaylist,
    this.artistAvatarUrl = '',
    this.artistReleases = const [],
    this.artistPlaylists = const [],
    this.isResolvingTarget = false,
    this.isResolvingAlbums = false,
    required this.onAlbumTap,
    this.initialShowPlaylists = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Profil Artiste (Avatar + Nom)
          ArtistGroupHeader(
            artistId: artistId,
            fallbackName: artistName,
            artistAvatarUrl: artistAvatarUrl,
            trackCount: tracks.length,
            isResolvingTarget: isResolvingTarget,
          ),
          const SizedBox(height: 8),

          // 2. Sorties & Albums Officiels de l'Artiste
          ArtistDiscographySection(
            artistName: artistName,
            artistId: artistId,
            searchQuery: searchQuery,
            initialShowPlaylists: initialShowPlaylists,
            autoExpandAlbum: matchedAlbum,
            autoExpandPlaylist: matchedPlaylist,
            artistReleases: artistReleases,
            artistPlaylists: artistPlaylists,
            isResolvingAlbums: isResolvingAlbums,
            onAlbumTap: onAlbumTap,
          ),

          // 3. Les Morceaux YouTube
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: tracks.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, idx) {
              final track = tracks[idx];
              return TrackTile(
                track: track,
                playlistContext: tracks,
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

/// Header for the artist group with avatar and navigation tap
class ArtistGroupHeader extends StatelessWidget {
  final String artistId;
  final String fallbackName;
  final String artistAvatarUrl;
  final int trackCount;
  final bool isResolvingTarget;

  const ArtistGroupHeader({
    super.key,
    required this.artistId,
    required this.fallbackName,
    this.artistAvatarUrl = '',
    required this.trackCount,
    this.isResolvingTarget = false,
  });

  @override
  Widget build(BuildContext context) {
    final Widget avatarWidget;
    if (artistAvatarUrl.isNotEmpty) {
      avatarWidget = AppNetworkImage(
        imageUrl: artistAvatarUrl,
        width: 36,
        height: 36,
        borderRadius: 18,
      );
    } else if (isResolvingTarget) {
      avatarWidget = const SkeletonBox(width: 36, height: 36, borderRadius: 18);
    } else {
      avatarWidget = Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppTheme.primaryPink.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          LucideIcons.user,
          size: 16,
          color: AppTheme.primaryPink,
        ),
      );
    }

    return InkWell(
      onTap: () {
        final audio = context.read<AudioProvider>();
        final artistObj = Artist(
          id: artistId,
          name: fallbackName,
          avatarUrl: artistAvatarUrl,
          bannerUrl: '',
          bio: 'Artiste Officiel',
          tracks: const [],
          albums: const [],
        );
        audio.selectArtistAndNavigate(artistObj);
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            avatarWidget,
            const SizedBox(width: 10),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      fallbackName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(LucideIcons.chevron_right, size: 14, color: AppTheme.textMuted),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Discography / Releases section displaying albums and playlists
class ArtistDiscographySection extends StatelessWidget {
  final String artistName;
  final String artistId;
  final String searchQuery;
  final Album? autoExpandAlbum;
  final Album? autoExpandPlaylist;
  final List<Album> artistReleases;
  final List<Album> artistPlaylists;
  final bool isResolvingAlbums;
  final ValueChanged<Album> onAlbumTap;
  final bool initialShowPlaylists;

  const ArtistDiscographySection({
    super.key,
    required this.artistName,
    required this.artistId,
    this.searchQuery = '',
    this.autoExpandAlbum,
    this.autoExpandPlaylist,
    this.artistReleases = const [],
    this.artistPlaylists = const [],
    this.isResolvingAlbums = false,
    required this.onAlbumTap,
    this.initialShowPlaylists = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isResolvingAlbums && autoExpandAlbum == null && autoExpandPlaylist == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2, bottom: 8),
              child: Row(
                children: const [
                  SkeletonBox(width: 12, height: 12, borderRadius: 6),
                  SizedBox(width: 6),
                  SkeletonBox(width: 140, height: 10, borderRadius: 4),
                ],
              ),
            ),
            SizedBox(
              height: 145,
              child: Row(
                children: const [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 100, height: 100, borderRadius: 14),
                      SizedBox(height: 6),
                      SkeletonBox(width: 90, height: 12, borderRadius: 4),
                      SizedBox(height: 4),
                      SkeletonBox(width: 60, height: 9, borderRadius: 4),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 1. Album Associé Direct
    if (autoExpandAlbum != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSubheader(
            icon: LucideIcons.disc,
            iconColor: AppTheme.accentPurple,
            title: 'ALBUM ASSOCIÉ',
          ),
          _buildHorizontalCarousel(context, [autoExpandAlbum!]),
          const SizedBox(height: 12),
        ],
      );
    }

    // 2. Playlist Associée Directe
    if (autoExpandPlaylist != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSubheader(
            icon: LucideIcons.list_music,
            iconColor: AppTheme.primaryPink,
            title: 'PLAYLIST ASSOCIÉE',
          ),
          _buildHorizontalCarousel(context, [autoExpandPlaylist!]),
          const SizedBox(height: 12),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildSubheader({required IconData icon, required Color iconColor, required String title}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 2, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 12, color: iconColor),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: AppTheme.textMuted,
              letterSpacing: 0.9,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalCarousel(BuildContext context, List<Album> items) {
    return SizedBox(
      height: 145,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, idx) {
          final album = items[idx];
          return InkWell(
            onTap: () => onAlbumTap(album),
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 100,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppNetworkImage(
                    imageUrl: album.coverUrl,
                    width: 100,
                    height: 100,
                    borderRadius: 14,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    album.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
