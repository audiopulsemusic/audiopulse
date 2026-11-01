class ApiConfig {
  String baseUrl;
  bool isConnected;
  String mode; // 'mock' | 'live'
  String? apiKey;
  String status; // 'online' | 'connecting' | 'offline' | 'mock_active'

  ApiConfig({
    this.baseUrl = 'https://api.musicpark.app/v1',
    this.isConnected = false,
    this.mode = 'mock',
    this.apiKey,
    this.status = 'mock_active',
  });

  ApiConfig copyWith({
    String? baseUrl,
    bool? isConnected,
    String? mode,
    String? apiKey,
    String? status,
  }) {
    return ApiConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      isConnected: isConnected ?? this.isConnected,
      mode: mode ?? this.mode,
      apiKey: apiKey ?? this.apiKey,
      status: status ?? this.status,
    );
  }
}
