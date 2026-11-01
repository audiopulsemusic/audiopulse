import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';
import '../models/track.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../theme/app_theme.dart';
import '../widgets/app_network_image.dart';
import '../widgets/track_tile.dart';
import '../services/database_service.dart';
import '../services/audio_fetch_service.dart';

class _LibraryAlbumItem {
  final String id;
  final String title;
  final String artist;
  final String artistId;
  final String coverUrl;
  final String ambientColor;
  final String genre;
  final List<Track> tracks;

  _LibraryAlbumItem({
    required this.id,
    required this.title,
    required this.artist,
    this.artistId = '',
    required this.coverUrl,
    required this.ambientColor,
    required this.genre,
    required this.tracks,
  });

  Album toAlbum() => Album(
    id: id,
    title: title,
    artist: artist,
    artistId: artistId.isNotEmpty
        ? artistId
        : (tracks.firstOrNull?.artistId ?? ''),
    coverUrl: coverUrl,
    releaseYear: tracks.firstOrNull?.releaseYear ?? DateTime.now().year,
    tracksCount: tracks.length,
    genre: genre,
    ambientColor: ambientColor,
    tracks: tracks,
  );
}

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  String _searchQuery = '';
  String _activeFilter = 'tracks'; // 'tracks', 'artists', 'albums'
  String? _expandedArtistKey;

  void _showAlbumBottomSheet(BuildContext context, _LibraryAlbumItem item) {
    final audio = context.read<AudioProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F131E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.only(top: 16, bottom: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        AppNetworkImage(
                          imageUrl: item.coverUrl,
                          width: 64,
                          height: 64,
                          borderRadius: 14,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${item.tracks.length} ${item.tracks.length > 1 ? "titres" : "titre"}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primaryPink,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            if (item.tracks.isNotEmpty) {
                              audio.playTrack(item.tracks.first, item.tracks);
                            }
                          },
                          icon: const Icon(LucideIcons.play, size: 14),
                          label: const Text(
                            'Tout lire',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryPink,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Divider(color: Colors.white10, height: 1),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      itemCount: item.tracks.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, idx) {
                        final track = item.tracks[idx];
                        return TrackTile(
                          track: track,
                          playlistContext: item.tracks,
                          showDownloadButton: true,
                          onTap: () {
                            Navigator.pop(context);
                            audio.playTrack(track, item.tracks);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final allTracks = context.select<AudioProvider, List<Track>>(
      (a) => a.allTracks,
    );

    final filteredTracks =
        allTracks.where((t) {
          final q = _searchQuery.toLowerCase().trim();
          return q.isEmpty ||
              t.title.toLowerCase().contains(q) ||
              t.artist.toLowerCase().contains(q) ||
              t.album.toLowerCase().contains(q);
        }).toList()..sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );

    final Map<String, ({String artistId, String avatarUrl, List<Track> tracks})>
    artistGroups = {};
    for (final t in filteredTracks) {
      final name = t.artist.trim().isNotEmpty
          ? t.artist.trim()
          : 'Artiste Inconnu';
      final avatar = t.artistAvatarUrl;
      if (!artistGroups.containsKey(name)) {
        artistGroups[name] = (
          artistId: t.artistId.trim(),
          avatarUrl: avatar,
          tracks: [t],
        );
      } else {
        artistGroups[name]!.tracks.add(t);
        if (artistGroups[name]!.avatarUrl.isEmpty && avatar.isNotEmpty) {
          artistGroups[name] = (
            artistId: artistGroups[name]!.artistId.isNotEmpty
                ? artistGroups[name]!.artistId
                : t.artistId.trim(),
            avatarUrl: avatar,
            tracks: artistGroups[name]!.tracks,
          );
        }
      }
    }
    final sortedArtistNames = artistGroups.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final Map<String, _LibraryAlbumItem> albumGroups = {};
    for (final track in filteredTracks) {
      final isSingle =
          track.album.isEmpty ||
          track.album == 'Single' ||
          track.album == 'Streaming Web' ||
          track.album == 'Hi-Fi Audio';

      final groupKey = isSingle
          ? 'single_${track.id}'
          : '${track.artist.toLowerCase().trim()}___${track.album.toLowerCase().trim()}';
      final groupTitle = isSingle ? track.title : track.album;

      if (!albumGroups.containsKey(groupKey)) {
        albumGroups[groupKey] = _LibraryAlbumItem(
          id: track.albumId.isNotEmpty ? track.albumId : groupKey,
          title: groupTitle,
          artist: track.artist,
          artistId: track.artistId,
          coverUrl: track.coverUrl,
          ambientColor: track.ambientColor,
          genre: isSingle ? 'Single' : 'Album',
          tracks: [track],
        );
      } else {
        albumGroups[groupKey]!.tracks.add(track);
      }
    }
    final sortedAlbums = albumGroups.values.toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0x3310B981),
                      Color(0x1F06B6D4),
                      Color(0x150A0D14),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0x3310B981)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1110B981),
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x3310B981),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0x4D10B981)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.library,
                                size: 11,
                                color: AppTheme.accentEmerald,
                              ),
                              SizedBox(width: 5),
                              Text(
                                'BIBLIOTHÈQUE UNIFIÉE',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.accentEmerald,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${allTracks.length} titres',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Bibliothèque',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Vos musiques, artistes et albums sauvegardés et hors-ligne.',
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
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xCC0E121B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x26FFFFFF)),
                ),
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  onSubmitted: (val) {
                    final q = val.trim();
                    if (q.isNotEmpty && filteredTracks.isEmpty) {
                      context.read<AudioProvider>().navigateToSearchWithQuery(q);
                    }
                  },
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Rechercher dans votre bibliothèque...',
                    hintStyle: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                    prefixIcon: const Icon(
                      LucideIcons.search,
                      size: 16,
                      color: AppTheme.accentEmerald,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () {
                                  context.read<AudioProvider>().navigateToSearchWithQuery(_searchQuery);
                                },
                                tooltip: 'Rechercher dans le catalogue en ligne',
                                icon: const Icon(
                                  LucideIcons.globe,
                                  size: 16,
                                  color: AppTheme.primaryPink,
                                ),
                              ),
                              IconButton(
                                onPressed: () => setState(() => _searchQuery = ''),
                                tooltip: 'Effacer',
                                icon: const Icon(
                                  LucideIcons.x,
                                  size: 15,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          )
                        : null,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _buildFilterChip(
                    label: 'Morceaux (${filteredTracks.length})',
                    icon: LucideIcons.music,
                    keyName: 'tracks',
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    label: 'Artistes (${sortedArtistNames.length})',
                    icon: LucideIcons.user,
                    keyName: 'artists',
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    label: 'Albums (${sortedAlbums.length})',
                    icon: LucideIcons.disc,
                    keyName: 'albums',
                  ),
                ],
              ),
              const SizedBox(height: 18),
            ],
          ),
        ),
        if (filteredTracks.isEmpty)
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              decoration: BoxDecoration(
                color: const Color(0x800E121B),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x1AFFFFFF)),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      _searchQuery.isEmpty ? LucideIcons.music_2 : LucideIcons.search_x,
                      size: 36,
                      color: _searchQuery.isEmpty
                          ? AppTheme.textMuted.withValues(alpha: 0.5)
                          : AppTheme.primaryPink.withValues(alpha: 0.8),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _searchQuery.isEmpty
                          ? 'Votre bibliothèque est vide pour le moment.'
                          : 'Ce morceau n\'existe pas dans votre base locale.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _searchQuery.isEmpty ? FontWeight.normal : FontWeight.w600,
                        color: _searchQuery.isEmpty ? AppTheme.textMuted : Colors.white,
                      ),
                    ),
                    if (_searchQuery.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Rechercher "$_searchQuery" sur le catalogue en ligne pour l\'écouter ou l\'ajouter.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          context.read<AudioProvider>().navigateToSearchWithQuery(_searchQuery);
                        },
                        icon: const Icon(LucideIcons.search, size: 14),
                        label: Text(
                          'Rechercher "$_searchQuery" en ligne',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryPink,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          )
        else if (_activeFilter == 'tracks')
          ..._buildTracksSlivers(filteredTracks)
        else if (_activeFilter == 'artists')
          ..._buildArtistsSlivers(
            sortedArtistNames,
            artistGroups,
            filteredTracks,
          )
        else if (_activeFilter == 'albums')
          ..._buildAlbumsSlivers(sortedAlbums, filteredTracks),

        if (_searchQuery.isNotEmpty && filteredTracks.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: TextButton.icon(
                  onPressed: () {
                    context.read<AudioProvider>().navigateToSearchWithQuery(_searchQuery);
                  },
                  icon: const Icon(
                    LucideIcons.search,
                    size: 14,
                    color: AppTheme.primaryPink,
                  ),
                  label: Text(
                    'Rechercher "$_searchQuery" dans le catalogue en ligne',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryPink,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    backgroundColor: const Color(0x1AEC4899),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Color(0x33EC4899)),
                    ),
                  ),
                ),
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 170)),
      ],
    );
  }

  Widget _buildFilterChip({
    required String label,
    required IconData icon,
    required String keyName,
  }) {
    final isSelected = _activeFilter == keyName;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeFilter = keyName),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0x3310B981)
                : const Color(0x1AFFFFFF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? AppTheme.accentEmerald
                  : const Color(0x22FFFFFF),
              width: isSelected ? 1.2 : 0.8,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected ? AppTheme.accentEmerald : AppTheme.textMuted,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, List<Track> tracksToPlay) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    final shuffled = List<Track>.from(tracksToPlay)..shuffle();
                    if (shuffled.isNotEmpty) {
                      context.read<AudioProvider>().playTrack(
                        shuffled.first,
                        shuffled,
                      );
                    }
                  },
                  icon: const Icon(
                    LucideIcons.shuffle,
                    size: 16,
                    color: AppTheme.accentEmerald,
                  ),
                  tooltip: 'Lecture aléatoire',
                ),
                IconButton(
                  onPressed: () {
                    if (tracksToPlay.isNotEmpty) {
                      context.read<AudioProvider>().playTrack(
                        tracksToPlay.first,
                        tracksToPlay,
                      );
                    }
                  },
                  icon: const Icon(
                    LucideIcons.play,
                    size: 16,
                    color: AppTheme.primaryPink,
                  ),
                  tooltip: 'Tout lire',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTracksSlivers(List<Track> tracks) {
    return [
      _buildSectionHeader(
        '${tracks.length} ${tracks.length > 1 ? "titres" : "titre"}',
        tracks,
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate((context, idx) {
          if (idx.isOdd) return const SizedBox(height: 8);
          final trackIndex = idx ~/ 2;
          final track = tracks[trackIndex];
          return TrackTile(
            track: track,
            playlistContext: tracks,
            showDownloadButton: true,
          );
        }, childCount: tracks.isNotEmpty ? tracks.length * 2 - 1 : 0),
      ),
    ];
  }

  List<Widget> _buildArtistsSlivers(
    List<String> sortedArtistNames,
    Map<String, ({String artistId, String avatarUrl, List<Track> tracks})>
    artistGroups,
    List<Track> allFilteredTracks,
  ) {
    return [
      _buildSectionHeader(
        '${sortedArtistNames.length} ${sortedArtistNames.length > 1 ? "artistes" : "artiste"}',
        allFilteredTracks,
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, idx) {
            if (idx.isOdd) return const SizedBox(height: 10);
            final itemIndex = idx ~/ 2;
            final artistName = sortedArtistNames[itemIndex];
            final group = artistGroups[artistName]!;
            final isExpanded = _expandedArtistKey == artistName;

            return Container(
              decoration: BoxDecoration(
                color: const Color(0x660E121B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x1FFFFFFF)),
              ),
              child: Column(
                children: [
                  InkWell(
                    onTap: () {
                      setState(() {
                        _expandedArtistKey = isExpanded ? null : artistName;
                      });
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          _ArtistAvatarWidget(
                            key: ValueKey(
                              'lib_artist_${artistName.toLowerCase()}',
                            ),
                            artistName: artistName,
                            artistId: group.artistId,
                            initialAvatarUrl: group.avatarUrl,
                            size: 44,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  artistName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${group.tracks.length} ${group.tracks.length > 1 ? "titres" : "titre"}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              final audio = context.read<AudioProvider>();
                              audio.setSelectedArtist(
                                Artist(
                                  id: group.artistId,
                                  name: artistName,
                                  avatarUrl: group.avatarUrl,
                                  bannerUrl: '',
                                  bio: '',
                                  isFollowing: false,
                                  tracks: group.tracks,
                                ),
                              );
                              audio.setActiveView('artist');
                            },
                            icon: const Icon(
                              LucideIcons.external_link,
                              size: 16,
                              color: AppTheme.textSecondary,
                            ),
                            tooltip: 'Ouvrir la page artiste',
                          ),
                          Icon(
                            isExpanded
                                ? LucideIcons.chevron_up
                                : LucideIcons.chevron_down,
                            size: 16,
                            color: AppTheme.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (isExpanded) ...[
                    const Divider(color: Colors.white10, height: 1),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: group.tracks.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, tIdx) {
                          final track = group.tracks[tIdx];
                          return TrackTile(
                            track: track,
                            playlistContext: group.tracks,
                            showDownloadButton: true,
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
          childCount: sortedArtistNames.isNotEmpty
              ? sortedArtistNames.length * 2 - 1
              : 0,
        ),
      ),
    ];
  }

  List<Widget> _buildAlbumsSlivers(
    List<_LibraryAlbumItem> sortedAlbums,
    List<Track> allFilteredTracks,
  ) {
    return [
      _buildSectionHeader(
        '${sortedAlbums.length} ${sortedAlbums.length > 1 ? "albums" : "album"}',
        allFilteredTracks,
      ),
      SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.0,
        ),
        delegate: SliverChildBuilderDelegate((context, idx) {
          final collection = sortedAlbums[idx];
          return _LibraryAlbumTile(
            collection: collection,
            onOpenBottomSheet: () => _showAlbumBottomSheet(context, collection),
          );
        }, childCount: sortedAlbums.length),
      ),
    ];
  }
}

class _LibraryAlbumTile extends StatelessWidget {
  final _LibraryAlbumItem collection;
  final VoidCallback onOpenBottomSheet;

  const _LibraryAlbumTile({
    required this.collection,
    required this.onOpenBottomSheet,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrent = context.select<AudioProvider, bool>(
      (a) => collection.tracks.any((t) => t.id == a.currentTrack?.id),
    );
    final isPlaying = context.select<AudioProvider, bool>(
      (a) => isCurrent && a.isPlaying,
    );

    return InkWell(
      onTap: () {
        if (collection.tracks.length > 1) {
          onOpenBottomSheet();
        } else if (collection.tracks.isNotEmpty) {
          final audio = context.read<AudioProvider>();
          audio.playTrack(collection.tracks.first, audio.allTracks);
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: isCurrent ? const Color(0x33EC4899) : const Color(0x800E121B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCurrent
                ? AppTheme.primaryPink.withValues(alpha: 0.6)
                : const Color(0x1AFFFFFF),
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AppNetworkImage(
                  imageUrl: collection.coverUrl,
                  fit: BoxFit.cover,
                  borderRadius: 16,
                ),
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Color(0xCC000000)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    collection.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '${collection.artist} • ${collection.tracks.length} ${collection.tracks.length > 1 ? "titres" : "titre"}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (isPlaying)
              const Positioned(
                top: 8,
                right: 8,
                child: CircleAvatar(
                  radius: 12,
                  backgroundColor: AppTheme.primaryPink,
                  child: Icon(
                    LucideIcons.volume_2,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ArtistAvatarWidget extends StatefulWidget {
  final String artistName;
  final String artistId;
  final String initialAvatarUrl;
  final double size;

  const _ArtistAvatarWidget({
    super.key,
    required this.artistName,
    required this.artistId,
    required this.initialAvatarUrl,
    this.size = 44,
  });

  @override
  State<_ArtistAvatarWidget> createState() => _ArtistAvatarWidgetState();
}

class _ArtistAvatarWidgetState extends State<_ArtistAvatarWidget> {
  static final Set<String> _inFlightArtistLookups = <String>{};
  String _avatarUrl = '';

  @override
  void initState() {
    super.initState();
    _avatarUrl = widget.initialAvatarUrl;
    _resolveAvatar();
  }

  @override
  void didUpdateWidget(_ArtistAvatarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.artistName != oldWidget.artistName) {
      _avatarUrl = widget.initialAvatarUrl;
      _resolveAvatar();
    } else if (widget.initialAvatarUrl.isNotEmpty &&
        widget.initialAvatarUrl != _avatarUrl) {
      _avatarUrl = widget.initialAvatarUrl;
    } else if (_avatarUrl.isEmpty) {
      _resolveAvatar();
    }
  }

  Future<void> _resolveAvatar() async {
    final currentArtist = widget.artistName.trim();
    if (currentArtist.isEmpty) return;

    // 1. Check local SQLite artists table
    final existing = await DatabaseService.instance.findArtistByName(
      currentArtist,
    );
    if (existing != null && existing.avatarUrl.isNotEmpty) {
      if (mounted && widget.artistName.trim() == currentArtist) {
        setState(() => _avatarUrl = existing.avatarUrl);
      }
      return;
    }

    // 2. Fallback: si l'artiste d'un morceau téléchargé n'a pas encore d'avatar en base,
    // on le récupère une seule fois en arrière-plan et on le persiste dans SQLite.
    final lookupKey = currentArtist.toLowerCase();
    if (!_inFlightArtistLookups.add(lookupKey)) return;
    try {
      final details = await AudioFetchService.instance.getArtistChannelDetails(
        currentArtist,
      );
      if (details != null && details.logoUrl.isNotEmpty) {
        await DatabaseService.instance.saveArtistIndex(
          currentArtist,
          avatarUrl: details.logoUrl,
        );
        if (mounted && widget.artistName.trim() == currentArtist) {
          setState(() => _avatarUrl = details.logoUrl);
        }
      }
    } catch (_) {
    } finally {
      _inFlightArtistLookups.remove(lookupKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_avatarUrl.isNotEmpty) {
      return AppNetworkImage(
        imageUrl: _avatarUrl,
        width: widget.size,
        height: widget.size,
        borderRadius: widget.size / 2,
      );
    }

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: const BoxDecoration(
        color: Color(0x33EC4899),
        shape: BoxShape.circle,
      ),
      child: Icon(
        LucideIcons.user,
        size: widget.size * 0.45,
        color: AppTheme.primaryPink,
      ),
    );
  }
}
