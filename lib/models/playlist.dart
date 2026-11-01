import 'track.dart';

class Playlist {
  final String id;
  final String title;
  final String description;
  final String coverUrl;
  final List<Track> tracks;
  final String createdBy;
  final bool isPublic;
  final String ambientColor;

  Playlist({
    required this.id,
    required this.title,
    required this.description,
    required this.coverUrl,
    required List<Track> tracks,
    required this.createdBy,
    this.isPublic = true,
    required this.ambientColor,
  }) : tracks = List.unmodifiable(tracks);

  Playlist copyWith({
    String? id,
    String? title,
    String? description,
    String? coverUrl,
    List<Track>? tracks,
    String? createdBy,
    bool? isPublic,
    String? ambientColor,
  }) {
    return Playlist(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      coverUrl: coverUrl ?? this.coverUrl,
      tracks: tracks ?? this.tracks,
      createdBy: createdBy ?? this.createdBy,
      isPublic: isPublic ?? this.isPublic,
      ambientColor: ambientColor ?? this.ambientColor,
    );
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      coverUrl: json['coverUrl'] as String? ?? '',
      tracks: (json['tracks'] as List<dynamic>?)
              ?.map((e) => Track.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdBy: json['createdBy'] as String? ?? 'You',
      isPublic: json['isPublic'] as bool? ?? true,
      ambientColor: json['ambientColor'] as String? ?? '#EC4899',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'coverUrl': coverUrl,
      'tracks': tracks.map((t) => t.toJson()).toList(),
      'createdBy': createdBy,
      'isPublic': isPublic,
      'ambientColor': ambientColor,
    };
  }
}
