class UserProfile {
  final String id;
  final String name;
  final String handle;
  final String avatarUrl;
  final String subscriptionPlan;
  final int playlistsCount;

  UserProfile({
    required this.id,
    required this.name,
    required this.handle,
    required this.avatarUrl,
    required this.subscriptionPlan,
    required this.playlistsCount,
  });

  factory UserProfile.defaultUser() {
    return UserProfile(
      id: 'usr_001',
      name: 'Alexandre Mercer',
      handle: '@alexmercer',
      avatarUrl:
          'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=300&q=80',
      subscriptionPlan: 'MusicPark Hi-Fi',
      playlistsCount: 12,
    );
  }
}
