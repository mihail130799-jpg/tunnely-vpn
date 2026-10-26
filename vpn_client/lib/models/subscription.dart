/// A subscription URL issued by the VPN provider; its servers are stored as
/// [ServerProfile]s with `subscriptionId == id`.
class Subscription {
  Subscription({
    required this.id,
    required this.url,
    required this.name,
    this.updatedAt,
    this.lastError,
    this.upload,
    this.download,
    this.total,
    this.expire,
  });

  final String id;
  final String url;
  final String name;
  final DateTime? updatedAt;

  /// User-facing text of the last failed refresh; null when the last refresh succeeded.
  final String? lastError;
  final int? upload;
  final int? download;
  final int? total;
  final DateTime? expire;

  bool get isInsecure => url.startsWith('http://');

  Subscription copyWith({
    String? name,
    DateTime? updatedAt,
    String? lastError,
    bool clearError = false,
    int? upload,
    int? download,
    int? total,
    DateTime? expire,
  }) =>
      Subscription(
        id: id,
        url: url,
        name: name ?? this.name,
        updatedAt: updatedAt ?? this.updatedAt,
        lastError: clearError ? null : (lastError ?? this.lastError),
        upload: upload ?? this.upload,
        download: download ?? this.download,
        total: total ?? this.total,
        expire: expire ?? this.expire,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'name': name,
        'updatedAt': updatedAt?.toIso8601String(),
        'lastError': lastError,
        'upload': upload,
        'download': download,
        'total': total,
        'expire': expire?.toIso8601String(),
      };

  factory Subscription.fromJson(Map<String, dynamic> j) => Subscription(
        id: j['id'] as String,
        url: j['url'] as String,
        name: j['name'] as String,
        updatedAt: j['updatedAt'] == null ? null : DateTime.parse(j['updatedAt'] as String),
        lastError: j['lastError'] as String?,
        upload: j['upload'] as int?,
        download: j['download'] as int?,
        total: j['total'] as int?,
        expire: j['expire'] == null ? null : DateTime.parse(j['expire'] as String),
      );
}
