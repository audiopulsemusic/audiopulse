import 'track.dart';
import 'album.dart';

class Artist {
  final String id;
  final String name;
  final String avatarUrl;
  final String bannerUrl;
  final String topicChannelId;
  final String bio;
  final bool isFollowing;
  final List<Track> tracks;
  final List<Album> albums;

  Artist({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.bannerUrl,
    this.topicChannelId = '',
    this.bio = '',
    this.isFollowing = false,
    this.tracks = const [],
    this.albums = const [],
  });

  Artist copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    String? bannerUrl,
    String? topicChannelId,
    String? bio,
    bool? isFollowing,
    List<Track>? tracks,
    List<Album>? albums,
  }) {
    return Artist(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      topicChannelId: topicChannelId ?? this.topicChannelId,
      bio: bio ?? this.bio,
      isFollowing: isFollowing ?? this.isFollowing,
      tracks: tracks ?? this.tracks,
      albums: albums ?? this.albums,
    );
  }

  factory Artist.fromJson(Map<String, dynamic> json) {
    return Artist(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String? ?? '',
      bannerUrl: json['bannerUrl'] as String? ?? '',
      topicChannelId: json['topicChannelId'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      isFollowing: json['isFollowing'] as bool? ?? false,
      tracks: (json['tracks'] as List<dynamic>?)
              ?.map((e) => Track.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      albums: (json['albums'] as List<dynamic>?)
              ?.map((e) => Album.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatarUrl': avatarUrl,
      'bannerUrl': bannerUrl,
      'topicChannelId': topicChannelId,
      'bio': bio,
      'isFollowing': isFollowing,
      'tracks': tracks.map((t) => t.toJson()).toList(),
      'albums': albums.map((a) => a.toJson()).toList(),
    };
  }
}
