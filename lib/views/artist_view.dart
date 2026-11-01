import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';
import '../models/artist.dart';
import '../models/album.dart';
import '../models/track.dart';
import '../services/audio_fetch_service.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_network_image.dart';
import '../widgets/album_playlist_stage.dart';
import '../widgets/track_tile.dart';

class ArtistView extends StatefulWidget {
  const ArtistView({super.key});

  @override
  State<ArtistView> createState() => _ArtistViewState();
}

class _ArtistViewState extends State<ArtistView> {
  Future<({String title, String logoUrl, String bannerUrl})?>? _detailsFuture;
  Future<({List<Album> releases, List<Album> playlists})>? _discographyFuture;
  String? _loadedArtistId;
  bool _showAllPopular = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final audio = context.read<AudioProvider>();
    final artist = audio.selectedArtist;
    if (artist != null && artist.id != _loadedArtistId) {
      _loadedArtistId = artist.id;
      _showAllPopular = false;
      _loadArtistData(artist);
    }
  }

  void _loadArtistData(Artist artist) {
    _detailsFuture = AudioFetchService.instance.getArtistChannelDetails(
      artist.name,
      artistId: artist.id,
    );

    _discographyFuture = AudioFetchService.instance.getArtistReleasesAndPlaylists(
      artist.name,
      artistId: artist.id,
    );

    // Indexer immédiatement l'artiste et sa discographie complète en base SQLite
    _discographyFuture!.then((data) {
      if (data.releases.isNotEmpty) {
        unawaited(DatabaseService.instance.saveAlbumsIndex(data.releases));
      }
      if (data.playlists.isNotEmpty) {
        unawaited(DatabaseService.instance.saveAlbumsIndex(data.playlists));
      }
      _detailsFuture?.then((details) {
        unawaited(DatabaseService.instance.saveArtistIndex(
          artist.name,
          artistId: artist.id,
          topicChannelId: artist.topicChannelId,
          avatarUrl: details?.logoUrl ?? artist.avatarUrl,
        ));
      });
    });
  }

  Future<void> _playArtistShuffle(AudioProvider audio, Artist artist, List<Album> releases) async {
    final List<Track> allPlayableTracks = List<Track>.from(artist.tracks);

    if (allPlayableTracks.isEmpty && releases.isNotEmpty) {
      try {
        final albumData = await AudioFetchService.instance.fetchAlbumDetailsAndTracks(
          Track(
            id: releases.first.id,
            title: releases.first.title,
            artist: artist.name,
            album: releases.first.title,
            duration: 120,
            coverUrl: releases.first.coverUrl,
            audioUrl: 'yt://${releases.first.id}',
            genre: 'Album',
          ),
        );
        allPlayableTracks.addAll(albumData.tracks);
      } catch (_) {}
    }

    if (allPlayableTracks.isNotEmpty) {
      final shuffled = List<Track>.from(allPlayableTracks)..shuffle();
      audio.playTrack(shuffled.first, shuffled);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lecture aléatoire : ${artist.name} (${shuffled.length} titres)'),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _showAlbumTracksBottomSheet(BuildContext context, Album album) {
    final matchTrack = Track(
      id: album.id,
      title: album.title,
      artist: album.artist,
      album: album.title,
      duration: 180,
      coverUrl: album.coverUrl,
      audioUrl: 'yt://${album.id}',
      genre: album.genre.isNotEmpty ? album.genre : 'Album',
      ambientColor: album.ambientColor,
    );

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
    final artist = context.select<AudioProvider, Artist?>((a) => a.selectedArtist);
    if (artist == null) {
      return const Center(child: Text('Aucun artiste sélectionné.', style: TextStyle(color: Colors.white)));
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 14, bottom: 150),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bouton Retour
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => context.read<AudioProvider>().setActiveView('search'),
                icon: const Icon(LucideIcons.arrow_left, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 6),
              const Text(
                'Retour à la recherche',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Hero Banner Redesignée
          FutureBuilder<({String title, String logoUrl, String bannerUrl})?>(
            future: _detailsFuture,
            builder: (context, snapshot) {
              final details = snapshot.data;
              final avatarUrl = details?.logoUrl.isNotEmpty == true
                  ? details!.logoUrl
                  : artist.avatarUrl;
              final bannerUrl = details?.bannerUrl.isNotEmpty == true
                  ? details!.bannerUrl
                  : avatarUrl;
              final displayName = details?.title.isNotEmpty == true
                  ? details!.title
                  : artist.name;

              return Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryPink.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    children: [
                      // Image d'arrière-plan
                      Positioned.fill(
                        child: bannerUrl.isNotEmpty
                            ? AppNetworkImage(
                                imageUrl: bannerUrl,
                                fit: BoxFit.cover,
                                borderRadius: 24,
                              )
                            : Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                              ),
                      ),

                      // Overlay sombre avec dégradé
                      Positioned.fill(
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFA05070B),
                                Color(0x9905070B),
                                Color(0x33000000),
                              ],
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              stops: [0.0, 0.6, 1.0],
                            ),
                          ),
                        ),
                      ),

                      // Contenu de la bannière : Avatar + Nom + Bouton Play
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: Row(
                          children: [
                            // Avatar
                            avatarUrl.isNotEmpty
                                ? Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white24, width: 2),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(28),
                                      child: AppNetworkImage(
                                        imageUrl: avatarUrl,
                                        width: 56,
                                        height: 56,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  )
                                : Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryPink.withValues(alpha: 0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(LucideIcons.user, size: 28, color: AppTheme.primaryPink),
                                  ),

                            const SizedBox(width: 14),

                            // Nom de l'artiste + Badge vérifié (sans "Artiste Officiel")
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      displayName,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: -0.5,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(LucideIcons.badge_check, size: 18, color: AppTheme.primaryPink),
                                ],
                              ),
                            ),

                            const SizedBox(width: 10),

                            // Bouton Play / Lecture Aléatoire
                            FutureBuilder<({List<Album> releases, List<Album> playlists})>(
                              future: _discographyFuture,
                              builder: (context, discSnap) {
                                final releases = discSnap.data?.releases ?? [];
                                return GestureDetector(
                                  onTap: () => _playArtistShuffle(context.read<AudioProvider>(), artist, releases),
                                  child: Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [AppTheme.primaryPink, AppTheme.accentPurple],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTheme.primaryPink.withValues(alpha: 0.5),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      LucideIcons.play,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 22),

          // 1. MORCEAUX POPULAIRES (En première place, 3 résultats max par défaut)
          if (artist.tracks.isNotEmpty) ...[
            _buildSectionHeader(
              icon: LucideIcons.music,
              iconColor: AppTheme.primaryPink,
              title: 'MORCEAUX POPULAIRES (${artist.tracks.length})',
              trailing: artist.tracks.length > 3
                  ? GestureDetector(
                      onTap: () {
                        setState(() {
                          _showAllPopular = !_showAllPopular;
                        });
                      },
                      child: Text(
                        _showAllPopular ? 'Réduire' : 'Voir tout',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryPink,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 10),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _showAllPopular ? artist.tracks.length : (artist.tracks.length > 3 ? 3 : artist.tracks.length),
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, idx) {
                final track = artist.tracks[idx];
                return TrackTile(
                  track: track,
                  playlistContext: artist.tracks,
                  showDownloadButton: true,
                );
              },
            ),
            const SizedBox(height: 22),
          ],

          // 2. Discographie Complète (Albums, Singles et Playlists)
          FutureBuilder<({List<Album> releases, List<Album> playlists})>(
            future: _discographyFuture,
            builder: (context, discSnapshot) {
              if (discSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: CircularProgressIndicator(color: AppTheme.primaryPink),
                  ),
                );
              }

              final allReleases = discSnapshot.data?.releases ?? [];
              final playlists = discSnapshot.data?.playlists ?? [];

              final albums = allReleases.where((a) => a.tracksCount > 1 && a.genre != 'Single').toList();
              final singles = allReleases.where((a) => a.tracksCount <= 1 || a.genre == 'Single').toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 2a. Sorties & Albums Officiels (> 1 piste)
                  if (albums.isNotEmpty) ...[
                    _buildSectionHeader(
                      icon: LucideIcons.disc,
                      iconColor: AppTheme.accentPurple,
                      title: 'SORTIES & ALBUMS OFFICIELS (${albums.length})',
                    ),
                    const SizedBox(height: 8),
                    _buildHorizontalCarousel(albums),
                    const SizedBox(height: 20),
                  ],

                  // 2b. Singles & Titres (1 piste)
                  if (singles.isNotEmpty) ...[
                    _buildSectionHeader(
                      icon: LucideIcons.disc_3,
                      iconColor: const Color(0xFF06B6D4),
                      title: 'SINGLES (${singles.length})',
                    ),
                    const SizedBox(height: 8),
                    _buildHorizontalCarousel(singles),
                    const SizedBox(height: 20),
                  ],

                  // 2c. Playlists Officielles
                  if (playlists.isNotEmpty) ...[
                    _buildSectionHeader(
                      icon: LucideIcons.list_music,
                      iconColor: AppTheme.primaryPink,
                      title: 'PLAYLISTS OFFICIELLES (${playlists.length})',
                    ),
                    const SizedBox(height: 8),
                    _buildHorizontalCarousel(playlists),
                    const SizedBox(height: 20),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required Color iconColor,
    required String title,
    Widget? trailing,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        ?trailing,
      ],
    );
  }

  Widget _buildHorizontalCarousel(List<Album> items) {
    return SizedBox(
      height: 155,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, idx) {
          final album = items[idx];
          return InkWell(
            onTap: () => _showAlbumTracksBottomSheet(context, album),
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 110,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      AppNetworkImage(
                        imageUrl: album.coverUrl,
                        width: 110,
                        height: 110,
                        borderRadius: 14,
                      ),
                      // Bottom-Right Tracks Count
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${album.tracksCount} pistes',
                            style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
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
