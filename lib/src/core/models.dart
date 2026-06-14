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
    required this.likes,
    required this.comments,
    required this.minutesAgo,
    required this.following,
  });

  final int id;
  final String author;
  final String avatarUrl;
  final String city;
  final String text;
  final String imageUrl;
  int likes;
  final List<FeedComment> comments;
  final int minutesAgo;
  final bool following;
  bool liked = false;
  bool saved = false;

  factory FeedPost.fromJson(Map<String, dynamic> json) {
    int parseInt(Object? v) => int.tryParse(v?.toString() ?? '') ?? 0;
    final comments = (json['comments'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(FeedComment.fromJson)
        .toList();
    final post = FeedPost(
      id: parseInt(json['id']),
      author: json['author']?.toString() ?? 'Anonymous',
      avatarUrl: json['avatarUrl']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? '',
      likes: parseInt(json['likes']),
      comments: comments,
      minutesAgo: parseInt(json['minutesAgo']),
      following: json['following'] != false,
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
    required this.likes,
    required this.liked,
  });

  final int id;
  final String author;
  final String text;
  final String avatarUrl;
  int likes;
  bool liked;

  factory FeedComment.fromJson(Map<String, dynamic> json) {
    int parseInt(Object? v) => int.tryParse(v?.toString() ?? '') ?? 0;
    return FeedComment(
      id: parseInt(json['id']),
      author: json['author']?.toString() ?? 'user',
      text: json['text']?.toString() ?? '',
      avatarUrl: json['avatarUrl']?.toString() ?? '',
      likes: parseInt(json['likes']),
      liked: json['liked'] == true,
    );
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
    required this.isRead,
    required this.created,
  });

  final int id;
  final String actor;
  final String verb;
  final String targetType;
  final String targetId;
  final String targetText;
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
    required this.lastMessage,
    required this.lastSender,
    required this.updated,
    required this.unreadCount,
    required this.lastReadAt,
  });

  final int id;
  final String otherUser;
  final String otherFullName;
  final String lastMessage;
  final String lastSender;
  final DateTime updated;
  final int unreadCount;
  final DateTime? lastReadAt;

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    int parseInt(Object? v) => int.tryParse(v?.toString() ?? '') ?? 0;
    return ConversationSummary(
      id: parseInt(json['id']),
      otherUser: json['otherUser']?.toString() ?? '',
      otherFullName: json['otherFullName']?.toString() ?? '',
      lastMessage: json['lastMessage']?.toString() ?? '',
      lastSender: json['lastSender']?.toString() ?? '',
      updated:
          DateTime.tryParse(json['updated']?.toString() ?? '') ??
          DateTime.now(),
      unreadCount: parseInt(json['unreadCount']),
      lastReadAt: DateTime.tryParse(json['lastReadAt']?.toString() ?? ''),
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
