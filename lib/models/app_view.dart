/// Strongly typed application navigation destinations
enum AppView {
  home,
  search,
  offline,
  settings,
  artist,
  album,
  playlist,
  queueImport,
  share;

  /// Parse from raw string for backwards compatibility / serialization
  static AppView fromString(String? value) {
    switch (value?.toLowerCase().trim()) {
      case 'search':
        return AppView.search;
      case 'offline':
        return AppView.offline;
      case 'library':
      case 'bibliotheque':
      case 'home':
        return AppView.home;
      case 'settings':
        return AppView.settings;
      case 'artist':
        return AppView.artist;
      case 'album':
        return AppView.album;
      case 'playlist':
        return AppView.playlist;
      case 'queueimport':
        return AppView.queueImport;
      case 'share':
      case 'partager':
        return AppView.share;
      default:
        return AppView.home;
    }
  }

  /// String identifier for views
  String get id => name;
}
