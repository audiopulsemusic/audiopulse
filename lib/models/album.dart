import 'track.dart';
import 'collection_type.dart';

class Album {
  final String id;
  final String title;
  final String artist;
  final String artistId;
  final String coverUrl;
  final int releaseYear;
  final int tracksCount;
  final String genre;
  final CollectionType collectionType;
  final String ambientColor;
  final List<Track> tracks;

  Album({
    required this.id,
    required this.title,
    required this.artist,
    this.artistId = '',
    required this.coverUrl,
    required this.releaseYear,
    required this.tracksCount,
    required this.genre,
    required this.ambientColor,
    List<Track> tracks = const [],
    CollectionType? collectionType,
  }) : collectionType = collectionType ?? CollectionType.fromWire(null, legacyGenre: genre),
       tracks = List.unmodifiable(tracks);

  Album copyWith({
    String? id,
    String? title,
    String? artist,
    String? artistId,
    String? coverUrl,
    int? releaseYear,
    int? tracksCount,
    String? genre,
    CollectionType? collectionType,
    String? ambientColor,
    List<Track>? tracks,
  }) {
    return Album(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      artistId: artistId ?? this.artistId,
      coverUrl: coverUrl ?? this.coverUrl,
      releaseYear: releaseYear ?? this.releaseYear,
      tracksCount: tracksCount ?? this.tracksCount,
      genre: genre ?? this.genre,
      collectionType: collectionType ?? this.collectionType,
      ambientColor: ambientColor ?? this.ambientColor,
      tracks: tracks ?? this.tracks,
    );
  }

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      artistId: json['artistId'] as String? ?? '',
      coverUrl: json['coverUrl'] as String? ?? '',
      releaseYear: (json['releaseYear'] as num?)?.toInt() ?? 2025,
      tracksCount: (json['tracksCount'] as num?)?.toInt() ?? 0,
      genre: json['genre'] as String? ?? '',
      collectionType: CollectionType.fromWire(
        json['collectionType'] ?? json['type'],
        legacyGenre: json['genre'] as String?,
      ),
      ambientColor: json['ambientColor'] as String? ?? '#8B5CF6',
      tracks: (json['tracks'] as List<dynamic>?)
              ?.map((e) => Track.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'artistId': artistId,
      'coverUrl': coverUrl,
      'releaseYear': releaseYear,
      'tracksCount': tracksCount,
      'genre': genre,
      'collectionType': collectionType.wireName,
      'ambientColor': ambientColor,
      'tracks': tracks.map((t) => t.toJson()).toList(),
    };
  }
}
