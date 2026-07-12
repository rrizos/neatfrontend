import 'package:flutter/foundation.dart' show kIsWeb;
import 'api.dart' show apiBaseUrl, webBaseUrl;

// Resolves media URLs so they are always HTTPS on web (avoids mixed-content
// blocks when the app is served from Netlify). Handles three cases:
//   1. Relative path (/media/...)          → prepend webBaseUrl or apiBaseUrl
//   2. Absolute HTTP server URL (http://IP) → rewrite to webBaseUrl path on web
//   3. Everything else (https:, data:, …)  → return unchanged
String _resolveMediaUrl(String url) {
  if (url.startsWith('/')) {
    return kIsWeb ? '$webBaseUrl$url' : '$apiBaseUrl$url';
  }
  if (kIsWeb && url.startsWith('http://')) {
    // Strip the HTTP origin and prepend the HTTPS Netlify origin so the
    // request goes through the Netlify proxy instead of being mixed-content.
    final uri = Uri.tryParse(url);
    if (uri != null) return '$webBaseUrl${uri.path}';
  }
  return url;
}

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

  Map<String, dynamic> toJson() => {
    'username': username,
    'fullName': fullName,
    'avatarUrl': avatarUrl,
  };
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
    this.isVerified = false,
    this.isAdmin = false,
    this.canCreateOfficialEvents = false,
    this.isBlocked = false,
    this.hasBlockedYou = false,
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
  final bool isVerified;
  final bool isAdmin;
  final bool canCreateOfficialEvents;
  final bool isBlocked;
  final bool hasBlockedYou;

  UserProfile copyWith({
    bool? isFollowing,
    bool? followsYou,
    int? followers,
    bool? isBlocked,
    bool? hasBlockedYou,
  }) => UserProfile(
    id: id, username: username, email: email, fullName: fullName,
    bio: bio, city: city, avatarUrl: avatarUrl,
    followers: followers ?? this.followers,
    following: following,
    isFollowing: isFollowing ?? this.isFollowing,
    followsYou: followsYou ?? this.followsYou,
    mutuals: mutuals, mutualsCount: mutualsCount, avatarZoomable: avatarZoomable,
    isVerified: isVerified, isAdmin: isAdmin,
    canCreateOfficialEvents: canCreateOfficialEvents,
    isBlocked: isBlocked ?? this.isBlocked,
    hasBlockedYou: hasBlockedYou ?? this.hasBlockedYou,
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
      isVerified: json['isVerified'] == true,
      isAdmin: json['isAdmin'] == true,
      canCreateOfficialEvents: json['canCreateOfficialEvents'] == true,
      isBlocked: json['isBlocked'] == true,
      hasBlockedYou: json['hasBlockedYou'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'email': email,
    'fullName': fullName,
    'bio': bio,
    'city': city,
    'avatarUrl': avatarUrl,
    'followers': followers,
    'following': following,
    'isFollowing': isFollowing,
    'followsYou': followsYou,
    'mutuals': mutuals.map((m) => m.toJson()).toList(),
    'mutualsCount': mutualsCount,
    'avatarZoomable': avatarZoomable,
    'isVerified': isVerified,
    'isAdmin': isAdmin,
    'canCreateOfficialEvents': canCreateOfficialEvents,
    'isBlocked': isBlocked,
    'hasBlockedYou': hasBlockedYou,
  };
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
    this.authorVerified = false,
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
  final bool authorVerified;
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
                url: _resolveMediaUrl(m['url']?.toString() ?? ''),
                duration: (m['duration'] as num?)?.toDouble(),
              ))
          .where((m) => m.url.isNotEmpty)
          .toList();
    } else {
      final imageUrl = json['imageUrl']?.toString() ?? '';
      media = imageUrl.isNotEmpty
          ? [MediaItem(type: 'image', url: _resolveMediaUrl(imageUrl))]
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
      authorVerified: json['authorVerified'] == true,
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
    this.pinned = false,
    this.likedByOwner = false,
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
  bool pinned;
  bool likedByOwner;

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
      pinned: json['pinned'] == true,
      likedByOwner: json['likedByOwner'] == true,
    );
    return c;
  }
}

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.actor,
    required this.actorAvatarUrl,
    required this.verb,
    required this.targetType,
    required this.targetId,
    required this.targetText,
    required this.imageUrl,
    required this.videoUrl,
    required this.isRead,
    required this.created,
  });

  final int id;
  final String actor;
  final String actorAvatarUrl;
  final String verb;
  final String targetType;
  final String targetId;
  final String targetText;
  final String imageUrl;
  final String videoUrl;
  final bool isRead;
  final DateTime created;

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    int parseInt(Object? v) => int.tryParse(v?.toString() ?? '') ?? 0;
    return NotificationItem(
      id: parseInt(json['id']),
      actor: json['actor']?.toString() ?? '',
      actorAvatarUrl: json['actorAvatarUrl']?.toString() ?? '',
      verb: json['verb']?.toString() ?? '',
      targetType: json['targetType']?.toString() ?? '',
      targetId: json['targetId']?.toString() ?? '',
      targetText: json['targetText']?.toString() ?? '',
      imageUrl: _resolveMediaUrl(json['imageUrl']?.toString() ?? ''),
      videoUrl: _resolveMediaUrl(json['videoUrl']?.toString() ?? ''),
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
    this.otherLastReadAt,
    this.isTyping = false,
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
  final DateTime? otherLastReadAt;
  final bool isTyping;

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
      otherLastReadAt: DateTime.tryParse(json['otherLastReadAt']?.toString() ?? ''),
      isTyping: json['otherIsTyping'] == true,
    );
  }
}

class MessageItem {
  const MessageItem({
    required this.id,
    required this.sender,
    required this.text,
    required this.created,
    this.reactions = const {},
  });

  final int id;
  final String sender;
  final String text;
  final DateTime created;
  final Map<String, List<String>> reactions;

  String? reactionFor(String username) {
    for (final entry in reactions.entries) {
      if (entry.value.contains(username)) return entry.key;
    }
    return null;
  }

  factory MessageItem.fromJson(Map<String, dynamic> json) {
    int parseInt(Object? v) => int.tryParse(v?.toString() ?? '') ?? 0;
    final rawReactions = json['reactions'];
    final reactions = <String, List<String>>{
      if (rawReactions is Map)
        for (final entry in rawReactions.entries)
          entry.key.toString(): (entry.value as List? ?? const [])
              .map((v) => v.toString())
              .toList(),
    };
    return MessageItem(
      id: parseInt(json['id']),
      sender: json['sender']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      created:
          DateTime.tryParse(json['created']?.toString() ?? '') ??
          DateTime.now(),
      reactions: reactions,
    );
  }
}

String initialFor(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.substring(0, 1).toUpperCase();
}
