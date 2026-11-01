import 'package:flutter/foundation.dart';
import '../../models/app_view.dart';
import '../../models/artist.dart';
import '../../models/album.dart';
import '../../models/playlist.dart';

/// Manages active views, selected details, and full screen / drawer overlays
class NavigationManager extends ChangeNotifier {
  AppView _activeView = AppView.home;
  Artist? _selectedArtist;
  Album? _selectedAlbum;
  Playlist? _selectedPlaylist;

  // Overlays
  bool _isFullPlayerOpen = false;
  bool _isQueueOpen = false;
  bool _isCreatePlaylistOpen = false;

  // Getters
  AppView get activeView => _activeView;
  String get activeViewId => _activeView.id;
  Artist? get selectedArtist => _selectedArtist;
  Album? get selectedAlbum => _selectedAlbum;
  Playlist? get selectedPlaylist => _selectedPlaylist;
  bool get isFullPlayerOpen => _isFullPlayerOpen;
  bool get isQueueOpen => _isQueueOpen;
  bool get isCreatePlaylistOpen => _isCreatePlaylistOpen;

  void setActiveView(dynamic view) {
    if (view is AppView) {
      _activeView = view;
    } else if (view is String) {
      _activeView = AppView.fromString(view);
    }
    notifyListeners();
  }

  void setSelectedArtist(Artist artist) {
    _selectedArtist = artist;
    notifyListeners();
  }

  void setSelectedAlbum(Album album) {
    _selectedAlbum = album;
    notifyListeners();
  }

  void setSelectedPlaylist(Playlist playlist) {
    _selectedPlaylist = playlist;
    notifyListeners();
  }

  void selectArtistAndNavigate(Artist artist) {
    _selectedArtist = artist;
    _activeView = AppView.artist;
    notifyListeners();
  }

  void selectAlbumAndNavigate(Album album) {
    _selectedAlbum = album;
    notifyListeners();
  }

  void openFullPlayer() {
    _isFullPlayerOpen = true;
    notifyListeners();
  }

  void closeFullPlayer() {
    _isFullPlayerOpen = false;
    notifyListeners();
  }

  void toggleQueue() {
    _isQueueOpen = !_isQueueOpen;
    notifyListeners();
  }

  void toggleCreatePlaylist() {
    _isCreatePlaylistOpen = !_isCreatePlaylistOpen;
    notifyListeners();
  }
}
