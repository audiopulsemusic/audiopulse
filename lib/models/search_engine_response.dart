import 'artist.dart';
import 'album.dart';
import 'track.dart';

/// Strongly typed sealed class representing the best match result
sealed class SearchBestMatch {
  const SearchBestMatch();

  factory SearchBestMatch.from(Object? match) {
    if (match is Artist) return ArtistSearchMatch(match);
    if (match is Album) return AlbumSearchMatch(match);
    if (match is Track) return TrackSearchMatch(match);
    if (match is SearchBestMatch) return match;
    throw ArgumentError('Unsupported best match type: ${match.runtimeType}');
  }
}

class ArtistSearchMatch extends SearchBestMatch {
  final Artist artist;
  const ArtistSearchMatch(this.artist);
}

class AlbumSearchMatch extends SearchBestMatch {
  final Album album;
  const AlbumSearchMatch(this.album);
}

class TrackSearchMatch extends SearchBestMatch {
  final Track track;
  const TrackSearchMatch(this.track);
}

/// Unified Search Engine Response with strongly typed collections and best match
class SearchEngineResponse {
  final SearchBestMatch? bestMatch;
  final List<Artist> artists;
  final List<Album> albums;
  final List<Album> playlists;
  final List<Track> tracks;

  SearchEngineResponse({
    Object? bestMatch,
    required this.artists,
    required this.albums,
    this.playlists = const [],
    required this.tracks,
  }) : bestMatch = bestMatch != null ? (bestMatch is SearchBestMatch ? bestMatch : SearchBestMatch.from(bestMatch)) : null;

  factory SearchEngineResponse.empty() {
    return SearchEngineResponse(
      bestMatch: null,
      artists: [],
      albums: [],
      playlists: [],
      tracks: [],
    );
  }

  /// Strongly typed getters
  Artist? get bestArtist => bestMatch is ArtistSearchMatch ? (bestMatch as ArtistSearchMatch).artist : null;
  Album? get bestAlbum => bestMatch is AlbumSearchMatch ? (bestMatch as AlbumSearchMatch).album : null;
  Track? get bestTrack => bestMatch is TrackSearchMatch ? (bestMatch as TrackSearchMatch).track : null;

  bool get isEmpty => bestMatch == null && artists.isEmpty && albums.isEmpty && playlists.isEmpty && tracks.isEmpty;
  bool get isNotEmpty => !isEmpty;
}
