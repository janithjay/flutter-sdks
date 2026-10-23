// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

/// An application that has used an [SSOSession].
class SSOSessionParticipant {
  final String appId;

  /// The application's name. Left out when the application can't be found.
  final String? appName;
  final String firstJoinedAt;
  final String lastActiveAt;

  const SSOSessionParticipant({
    required this.appId,
    this.appName,
    required this.firstJoinedAt,
    required this.lastActiveAt,
  });

  factory SSOSessionParticipant.fromMap(Map<dynamic, dynamic> map) => SSOSessionParticipant(
        appId: map['appId'] as String? ?? '',
        appName: map['appName'] as String?,
        firstJoinedAt: map['firstJoinedAt'] as String? ?? '',
        lastActiveAt: map['lastActiveAt'] as String? ?? '',
      );
}

/// A live SSO session of the signed-in user, as recorded by the ThunderID server.
///
/// This is a server record, distinct from the tokens the SDK stores for the signed-in user.
class SSOSession {
  final String id;
  final String userId;
  final String authenticatedAt;
  final String createdAt;
  final String lastActiveAt;
  final String? absoluteExpiresAt;
  final String? idleExpiresAt;
  final String? creationIp;
  final String? lastActiveIp;
  final String? userAgent;

  /// Whether this session issued the access token the request was made with. Every session can be
  /// false, for example when the token came from an earlier grant of the same application.
  final bool isCurrent;

  /// The applications that have used the session, first joined first.
  final List<SSOSessionParticipant> participants;

  const SSOSession({
    required this.id,
    required this.userId,
    required this.authenticatedAt,
    required this.createdAt,
    required this.lastActiveAt,
    this.absoluteExpiresAt,
    this.idleExpiresAt,
    this.creationIp,
    this.lastActiveIp,
    this.userAgent,
    this.isCurrent = false,
    this.participants = const [],
  });

  factory SSOSession.fromMap(Map<dynamic, dynamic> map) => SSOSession(
        id: map['id'] as String? ?? '',
        userId: map['userId'] as String? ?? '',
        authenticatedAt: map['authenticatedAt'] as String? ?? '',
        createdAt: map['createdAt'] as String? ?? '',
        lastActiveAt: map['lastActiveAt'] as String? ?? '',
        absoluteExpiresAt: map['absoluteExpiresAt'] as String?,
        idleExpiresAt: map['idleExpiresAt'] as String?,
        creationIp: map['creationIp'] as String?,
        lastActiveIp: map['lastActiveIp'] as String?,
        userAgent: map['userAgent'] as String?,
        isCurrent: map['isCurrent'] as bool? ?? false,
        participants: (map['participants'] as List? ?? const [])
            .map((p) => SSOSessionParticipant.fromMap(p as Map))
            .toList(),
      );
}

/// A page of SSO sessions returned by `GET /sessions/me`.
class SSOSessionListResponse {
  final int totalResults;
  final int startIndex;
  final int count;
  final List<SSOSession> sessions;

  const SSOSessionListResponse({
    this.totalResults = 0,
    this.startIndex = 0,
    this.count = 0,
    this.sessions = const [],
  });

  factory SSOSessionListResponse.fromMap(Map<dynamic, dynamic> map) => SSOSessionListResponse(
        totalResults: (map['totalResults'] as num?)?.toInt() ?? 0,
        startIndex: (map['startIndex'] as num?)?.toInt() ?? 0,
        count: (map['count'] as num?)?.toInt() ?? 0,
        sessions: (map['sessions'] as List? ?? const [])
            .map((s) => SSOSession.fromMap(s as Map))
            .toList(),
      );
}
