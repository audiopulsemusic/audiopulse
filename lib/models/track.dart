class Track {
  final String id;
  final String title;
  final String artist;
  final String artistId;
  final String album;
  final String albumId;
  final String coverUrl;
  final String audioUrl;
  final int duration; // in seconds
  final String genre;
  final int releaseYear;
  final bool isExplicit;
  final String ambientColor; // e.g. '#8B5CF6'
  final bool isDownloaded;
  final String? localFilePath;
  final bool isFavorite;
  final String? lyrics;
  final String source; // 'music' (InnerTube YTM) or 'youtube' (YouTube Video)
  final int bitrate; // in kbps (e.g. 128, 256, 320)
  final String artistAvatarUrl;

  int get displayBitrate => bitrate;

  Track({
    required this.id,
    required this.title,
    required this.artist,
    this.artistId = '',
    this.album = 'Single',
    this.albumId = '',
    required this.coverUrl,
    this.audioUrl = '',
    required this.duration,
    this.genre = 'Electro',
    this.releaseYear = 2025,
    this.isExplicit = false,
    this.ambientColor = '#EC4899',
    this.isDownloaded = false,
    this.localFilePath,
    this.isFavorite = false,
    this.lyrics,
    this.source = 'music',
    this.bitrate = 0,
    this.artistAvatarUrl = '',
  });

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? artistId,
    String? album,
    String? albumId,
    String? coverUrl,
    String? audioUrl,
    int? duration,
    String? genre,
    int? releaseYear,
    bool? isExplicit,
    String? ambientColor,
    bool? isDownloaded,
    String? localFilePath,
    bool clearLocalFilePath = false,
    bool? isFavorite,
    String? lyrics,
    String? source,
    int? bitrate,
    String? artistAvatarUrl,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      artistId: artistId ?? this.artistId,
      album: album ?? this.album,
      albumId: albumId ?? this.albumId,
      coverUrl: coverUrl ?? this.coverUrl,
      audioUrl: audioUrl ?? this.audioUrl,
      duration: duration ?? this.duration,
      genre: genre ?? this.genre,
      releaseYear: releaseYear ?? this.releaseYear,
      isExplicit: isExplicit ?? this.isExplicit,
      ambientColor: ambientColor ?? this.ambientColor,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      localFilePath: clearLocalFilePath ? null : (localFilePath ?? this.localFilePath),
      isFavorite: isFavorite ?? this.isFavorite,
      lyrics: lyrics ?? this.lyrics,
      source: source ?? this.source,
      bitrate: bitrate ?? this.bitrate,
      artistAvatarUrl: artistAvatarUrl ?? this.artistAvatarUrl,
    );
  }

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      artistId: json['artistId'] as String? ?? '',
      album: json['album'] as String? ?? 'Single',
      albumId: json['albumId'] as String? ?? '',
      coverUrl: json['coverUrl'] as String? ?? '',
      audioUrl: json['audioUrl'] as String? ?? '',
      duration: (json['duration'] as num?)?.toInt() ?? 180,
      genre: json['genre'] as String? ?? 'Electro',
      releaseYear: (json['releaseYear'] as num?)?.toInt() ?? 2025,
      isExplicit: json['isExplicit'] as bool? ?? false,
      ambientColor: json['ambientColor'] as String? ?? '#EC4899',
      isDownloaded: json['isDownloaded'] as bool? ?? false,
      localFilePath: json['localFilePath'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      lyrics: json['lyrics'] as String?,
      source: json['source'] as String? ?? 'music',
      bitrate: (json['bitrate'] as num?)?.toInt() ?? 0,
      artistAvatarUrl: json['artistAvatarUrl'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'artistId': artistId,
      'album': album,
      'albumId': albumId,
      'coverUrl': coverUrl,
      'audioUrl': audioUrl,
      'duration': duration,
      'genre': genre,
      'releaseYear': releaseYear,
      'isExplicit': isExplicit,
      'ambientColor': ambientColor,
      'isDownloaded': isDownloaded,
      'localFilePath': localFilePath,
      'isFavorite': isFavorite,
      'lyrics': lyrics,
      'source': source,
      'bitrate': bitrate,
      'artistAvatarUrl': artistAvatarUrl,
    };
  }
}
