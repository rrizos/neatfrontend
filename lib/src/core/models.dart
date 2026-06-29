class MutualUser {
  const MutualUser({
    required this.username,
    required this.fullName,
    required this.avatarUrl,
  });
  final String username;
  final String fullName;
  final String avatarUrl;

  factory MutualUser.fromJson(Map<String, dynamic> json) => MutualUser(
    username: json['username']?.toString() ?? '',
    fullName: json['fullName']?.toString() ?? '',
    avatarUrl: json['avatarUrl']?.toString() ?? '',
  );
}

class MediaItem {
  const MediaItem({required this.type, required this.url, this.duration});
  final String type; // 'image' or 'video'
  final String url;
  final double? duration;
  bool get isVideo => type == 'video';
  bool get isImage => type == 'image';
}

class AuthSession {
  const AuthSession({required this.token, required this.user});
  final String token;
  final UserProfile user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      token: json['token']?.toString() ?? '',
      user: UserProfile.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    required this.email,
    required this.fullName,
    required this.bio,
    required this.city,
    required this.avatarUrl,
    required this.followers,
    required this.following,
    required this.isFollowing,
    this.followsYou = false,
    this.mutuals = const [],
    this.mutualsCount = 0,
    this.avatarZoomable = true,
  });
  final int id;
  final String username;
  final String email;
  final String fullName;
  final String bio;
  final String city;
  final String avatarUrl;
  final int followers;
  final int following;
  final bool isFollowing;
  final bool followsYou;
  final List<MutualUser> mutuals;
  final int mutualsCount;
  final bool avatarZoomable;

  UserProfile copyWith({bool? isFollowing, bool? followsYou, int? followers}) => UserProfile(
    id: id, username: username, email: email, fullName: fullName,
    bio: bio, city: city, avatarUrl: avatarUrl,
    followers: followers ?? this.followers,
    following: following,
    isFollowing: isFollowing ?? this.isFollowing,
    followsYou: followsYou ?? this.followsYou,
    mutuals: mutuals, mutualsCount: mutualsCount, avatarZoomable: avatarZoomable,
  );

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    int parseInt(Object? v) => int.tryParse(v?.toString() ?? '') ?? 0;
    return UserProfile(
      id: parseInt(json['id']),
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? '',
      bio: json['bio']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      avatarUrl: json['avatarUrl']?.toString() ?? '',
      followers: parseInt(json['followers']),
      following: parseInt(json['following']),
      isFollowing: json['isFollowing'] == true,
      followsYou: json['followsYou'] == true ||
          json['isFollowedBy'] == true ||
          json['follows_you'] == true ||
          json['is_followed_by'] == true,
      mutuals: (json['mutuals'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MutualUser.fromJson)
          .toList(),
      mutualsCount: parseInt(json['mutualsCount']),
      avatarZoomable: json['avatarZoomable'] != false,
    );
  }
}

class FeedPost {
  FeedPost({
    required this.id,
    required this.author,
    required this.avatarUrl,
    required this.city,
    required this.text,
    required this.imageUrl,
    required this.media,
    required this.likes,
    required this.comments,
    required this.minutesAgo,
    required this.following,
    required this.likedByFollowing,
  });

  final int id;
  final String author;
  final String avatarUrl;
  final String city;
  final String text;
  final String imageUrl;
  final List<MediaItem> media;
  int likes;
  final List<FeedComment> comments;
  final int minutesAgo;
  final bool following;
  final List<String> likedByFollowing;
  bool liked = false;
  bool saved = false;

  factory FeedPost.fromJson(Map<String, dynamic> json) {
    int parseInt(Object? v) => int.tryParse(v?.toString() ?? '') ?? 0;
    final comments = (json['comments'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(FeedComment.fromJson)
        .toList();
    final likedByFollowing = (json['likedByFollowing'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList();

    // Parse media array; fall back to legacy imageUrl for old posts
    final rawMedia = json['media'];
    List<MediaItem> media;
    if (rawMedia is List && rawMedia.isNotEmpty) {
      media = rawMedia
          .whereType<Map<String, dynamic>>()
          .map((m) => MediaItem(
                type: m['type']?.toString() ?? 'image',
                url: m['url']?.toString() ?? '',
                duration: (m['duration'] as num?)?.toDouble(),
              ))
          .where((m) => m.url.isNotEmpty)
          .toList();
    } else {
      final imageUrl = json['imageUrl']?.toString() ?? '';
      media = imageUrl.isNotEmpty
          ? [MediaItem(type: 'image', url: imageUrl)]
          : [];
    }

    final post = FeedPost(
      id: parseInt(json['id']),
      author: json['author']?.toString() ?? 'Anonymous',
      avatarUrl: json['avatarUrl']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? '',
      media: media,
      likes: parseInt(json['likes']),
      comments: comments,
      minutesAgo: parseInt(json['minutesAgo']),
      following: json['following'] != false,
      likedByFollowing: likedByFollowing,
    );
    post.liked = json['liked'] == true;
    post.saved = json['saved'] == true;
    return post;
  }
}

class FeedComment {
  FeedComment({
    required this.id,
    required this.author,
    required this.text,
    required this.avatarUrl,
    required this.imageUrl,
    required this.parentId,
    required this.createdAt,
    required this.likes,
    required this.liked,
    required this.replies,
  });

  final int id;
  final String author;
  final String text;
  final String avatarUrl;
  final String imageUrl;
  final int? parentId;
  final String createdAt;
  final List<FeedComment> replies;
  int likes;
  bool liked;

  factory FeedComment.fromJson(Map<String, dynamic> json) {
    int parseInt(Object? v) => int.tryParse(v?.toString() ?? '') ?? 0;
    final replies = (json['replies'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(FeedComment.fromJson)
        .toList();
    final c = FeedComment(
      id: parseInt(json['id']),
      author: json['author']?.toString() ?? 'user',
      text: json['text']?.toString() ?? '',
      avatarUrl: json['avatarUrl']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? '',
      parentId: json['parentId'] != null ? parseInt(json['parentId']) : null,
      createdAt: json['created']?.toString() ?? '',
      likes: parseInt(json['likes']),
      liked: json['liked'] == true,
      replies: replies,
    );
    return c;
  }
}

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.actor,
    required this.verb,
    required this.targetType,
    required this.targetId,
    required this.targetText,
    required this.imageUrl,
    required this.isRead,
    required this.created,
  });

  final int id;
  final String actor;
  final String verb;
  final String targetType;
  final String targetId;
  final String targetText;
  final String imageUrl;
  final bool isRead;
  final DateTime created;

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    int parseInt(Object? v) => int.tryParse(v?.toString() ?? '') ?? 0;
    return NotificationItem(
      id: parseInt(json['id']),
      actor: json['actor']?.toString() ?? '',
      verb: json['verb']?.toString() ?? '',
      targetType: json['targetType']?.toString() ?? '',
      targetId: json['targetId']?.toString() ?? '',
      targetText: json['targetText']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? '',
      isRead: json['isRead'] == true,
      created:
          DateTime.tryParse(json['created']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.otherUser,
    required this.otherFullName,
    required this.otherAvatarUrl,
    required this.lastMessage,
    required this.lastSender,
    required this.updated,
    required this.unreadCount,
    required this.lastReadAt,
    this.otherLastActive,
  });

  final int id;
  final String otherUser;
  final String otherFullName;
  final String otherAvatarUrl;
  final String lastMessage;
  final String lastSender;
  final DateTime updated;
  final int unreadCount;
  final DateTime? lastReadAt;
  final DateTime? otherLastActive;

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    int parseInt(Object? v) => int.tryParse(v?.toString() ?? '') ?? 0;
    return ConversationSummary(
      id: parseInt(json['id']),
      otherUser: json['otherUser']?.toString() ?? '',
      otherFullName: json['otherFullName']?.toString() ?? '',
      otherAvatarUrl: json['otherAvatarUrl']?.toString() ?? '',
      lastMessage: json['lastMessage']?.toString() ?? '',
      lastSender: json['lastSender']?.toString() ?? '',
      updated:
          DateTime.tryParse(json['updated']?.toString() ?? '') ??
          DateTime.now(),
      unreadCount: parseInt(json['unreadCount']),
      lastReadAt: DateTime.tryParse(json['lastReadAt']?.toString() ?? ''),
      otherLastActive: DateTime.tryParse(json['otherLastActive']?.toString() ?? ''),
    );
  }
}

class MessageItem {
  const MessageItem({
    required this.id,
    required this.sender,
    required this.text,
    required this.created,
  });

  final int id;
  final String sender;
  final String text;
  final DateTime created;

  factory MessageItem.fromJson(Map<String, dynamic> json) {
    int parseInt(Object? v) => int.tryParse(v?.toString() ?? '') ?? 0;
    return MessageItem(
      id: parseInt(json['id']),
      sender: json['sender']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      created:
          DateTime.tryParse(json['created']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

String initialFor(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.substring(0, 1).toUpperCase();
}
