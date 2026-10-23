// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/i18n/thunderid_i18n.dart';
import 'package:thunderid_flutter/src/widgets/internal/platform_logos.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

const _channel = MethodChannel('dev.thunderid/sdk');

Map<Object?, Object?> _session(
  String id, {
  String? userAgent,
  bool isCurrent = false,
  String? appName,
}) =>
    <Object?, Object?>{
      'id': id,
      'userId': 'user-1',
      'authenticatedAt': '2026-10-21T09:00:00Z',
      'createdAt': '2026-10-21T09:00:00Z',
      'lastActiveAt': '2026-10-21T09:05:00Z',
      'lastActiveIp': '203.0.113.24',
      'userAgent': userAgent,
      'isCurrent': isCurrent,
      'participants': <Object?>[
        if (appName != null)
          <Object?, Object?>{'appId': 'app-1', 'appName': appName, 'firstJoinedAt': '', 'lastActiveAt': ''},
      ],
    };

SSOSession _model(String id, {String? userAgent, bool isCurrent = false, String? appName}) =>
    SSOSession.fromMap(_session(id, userAgent: userAgent, isCurrent: isCurrent, appName: appName));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final log = <MethodCall>[];
  var sessions = <Map<Object?, Object?>>[];
  Object? revokeError;

  setUp(() {
    log.clear();
    revokeError = null;
    sessions = [
      _session('s1', userAgent: 'ThunderID-Android/1.4.0 (Android 11; Redmi Note 8 Pro)', isCurrent: true, appName: 'Quickstart'),
      _session('s2', userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/129.0 Safari/537.36'),
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      (call) async {
        log.add(call);
        switch (call.method) {
          case 'initialize':
            return true;
          case 'isSignedIn':
            return false;
          case 'getUserSessions':
            return <Object?, Object?>{
              'totalResults': sessions.length,
              'startIndex': 0,
              'count': sessions.length,
              'sessions': sessions,
            };
          case 'revokeUserSession':
          case 'revokeUserSessions':
            if (revokeError != null) throw revokeError!;
            final id = (call.arguments as Map)['sessionId'];
            sessions = sessions.where((s) => call.method == 'revokeUserSessions' ? s['isCurrent'] == true : s['id'] != id).toList();
            return null;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
  });

  group('client', () {
    const config = ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test');

    test('getUserSessions sends the paging values and decodes the page', () async {
      final client = ThunderIDClient();
      await client.initialize(config);

      final page = await client.getUserSessions(limit: 5, offset: 10);

      final call = log.firstWhere((c) => c.method == 'getUserSessions');
      expect(call.arguments, {'limit': 5, 'offset': 10});
      expect(page.totalResults, 2);
      expect(page.sessions.first.isCurrent, true);
      expect(page.sessions.first.participants.first.appName, 'Quickstart');
    });

    test('revokeUserSession sends the identifier and rejects a blank one', () async {
      final client = ThunderIDClient();
      await client.initialize(config);

      await client.revokeUserSession('s2');
      expect(log.last.arguments, {'sessionId': 's2'});

      expect(
        () => client.revokeUserSession(' '),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.invalidInput)),
      );
    });

    test('revokeUserSessions sends exceptCurrent', () async {
      final client = ThunderIDClient();
      await client.initialize(config);

      await client.revokeUserSessions(exceptCurrent: true);

      expect(log.last.method, 'revokeUserSessions');
      expect(log.last.arguments, {'exceptCurrent': true});
    });

    test('session calls require initialization', () {
      expect(
        () => ThunderIDClient().getUserSessions(),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.sdkNotInitialized)),
      );
    });

    test('a NOT_FOUND from the native SDK reads as already revoked', () async {
      revokeError = PlatformException(code: 'NOT_FOUND', message: 'Not found');
      final client = ThunderIDClient();
      await client.initialize(config);

      try {
        await client.revokeUserSession('gone');
        fail('Expected not found');
      } catch (e) {
        expect(isAlreadyRevoked(e), true);
      }
    });
  });

  group('display', () {
    test('describeUserAgent reads browsers and mobile SDKs', () {
      expect(
        describeUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/129.0 Safari/537.36 Edg/129.0'),
        const UserAgentDescription(browser: 'Edge', os: 'Windows'),
      );
      expect(
        describeUserAgent('ThunderID-iOS/1.4.0 (iOS 15.8; iPhone 7)'),
        const UserAgentDescription(os: 'iOS', device: 'iPhone 7', isApp: true),
      );
      expect(
        describeUserAgent('ThunderID-Android/1.4.0 (Android 11)'),
        const UserAgentDescription(os: 'Android', isApp: true),
      );
      expect(describeUserAgent(null), const UserAgentDescription());
    });

    test('deviceLabel names a native app by its device, and a browser by the client and the place', () {
      final i18n = ThunderIDI18n(null);
      expect(
        deviceLabel(_model('s1', userAgent: 'ThunderID-Android/1.4.0 (Android 11; Redmi Note 8 Pro)', appName: 'Quickstart'), i18n),
        'Redmi Note 8 Pro',
      );
      expect(
        deviceLabel(_model('s1', userAgent: 'ThunderID-Android/1.4.0 (Android 11)', appName: 'Quickstart'), i18n),
        'Quickstart on Android',
      );
      expect(deviceLabel(_model('s2', userAgent: 'Mozilla/5.0 (X11; Linux x86_64) Firefox/131.0'), i18n), 'Firefox on Linux');
      expect(deviceLabel(_model('s3'), i18n), 'Unknown device');
    });

    test('groupSessionsByOs puts the current group first', () {
      final groups = groupSessionsByOs([
        _model('a', userAgent: 'Mozilla/5.0 (Windows NT 10.0) Firefox/131.0'),
        _model('b', userAgent: 'ThunderID-iOS/1.4.0 (iOS 15.8; iPhone 7)', isCurrent: true),
        _model('c', userAgent: 'Mozilla/5.0 (Windows NT 10.0) Chrome/129.0'),
      ]);

      expect(groups.map((g) => g.os), ['iOS', 'Windows']);
      expect(groups.last.sessions.map((s) => s.id), ['a', 'c']);
    });
  });

  group('BaseActiveSessions', () {
    Widget wrap(Widget child) => MaterialApp(
          home: Scaffold(
            body: ThunderIDProvider(
              config: const ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test'),
              child: child,
            ),
          ),
        );

    testWidgets('loads the sessions and counts the others', (tester) async {
      late ActiveSessionsState latest;
      await tester.pumpWidget(wrap(BaseActiveSessions(builder: (context, state) {
        latest = state;
        return const SizedBox.shrink();
      },),),);
      await tester.pumpAndSettle();

      expect(latest.sessions.map((s) => s.id), ['s1', 's2']);
      expect(latest.otherCount, 1);
      expect(latest.error, isNull);
    });

    testWidgets('revokes a session and reloads the list', (tester) async {
      late ActiveSessionsState latest;
      var revoked = 0;
      await tester.pumpWidget(wrap(BaseActiveSessions(
        onRevoked: () => revoked++,
        builder: (context, state) {
          latest = state;
          return const SizedBox.shrink();
        },
      ),),);
      await tester.pumpAndSettle();

      await latest.revoke('s2');
      await tester.pumpAndSettle();

      expect(latest.sessions.map((s) => s.id), ['s1']);
      expect(revoked, 1);
    });

    testWidgets('treats a session that is already gone as revoked', (tester) async {
      late ActiveSessionsState latest;
      await tester.pumpWidget(wrap(BaseActiveSessions(builder: (context, state) {
        latest = state;
        return const SizedBox.shrink();
      },),),);
      await tester.pumpAndSettle();

      revokeError = PlatformException(code: 'NOT_FOUND', message: 'Not found');
      await latest.revoke('s2');
      await tester.pumpAndSettle();

      expect(latest.error, isNull);
      expect(log.where((c) => c.method == 'getUserSessions').length, 2);
    });

    testWidgets('shows a revoke failure', (tester) async {
      late ActiveSessionsState latest;
      await tester.pumpWidget(wrap(BaseActiveSessions(builder: (context, state) {
        latest = state;
        return const SizedBox.shrink();
      },),),);
      await tester.pumpAndSettle();

      revokeError = PlatformException(code: 'SERVER_ERROR', message: 'boom');
      await latest.revokeOthers();
      await tester.pumpAndSettle();

      expect(latest.error, 'An error occurred while revoking the session. Please try again.');
    });
  });

  group('ActiveSessions', () {
    testWidgets('summarizes the sessions by operating system', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ThunderIDProvider(
            config: ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test'),
            child: ActiveSessions(),
          ),
        ),
      ),);
      await tester.pumpAndSettle();

      expect(find.text('Active sessions'), findsOneWidget);
      expect(find.text('1 session on Android'), findsOneWidget);
      expect(find.text('1 session on macOS'), findsOneWidget);
      expect(find.text('Manage sessions'), findsOneWidget);

      await tester.tap(find.text('Manage sessions'));
      await tester.pumpAndSettle();

      expect(find.text('Redmi Note 8 Pro'), findsOneWidget);
      expect(find.text('Quickstart'), findsOneWidget);
      expect(find.text('This device'), findsOneWidget);
      expect(find.text('Revoke all other sessions'), findsOneWidget);
    });

    testWidgets('confirms before signing out the other sessions', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ThunderIDProvider(
            config: ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test'),
            child: ActiveSessions(),
          ),
        ),
      ),);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('thunderid-action-manageSessions')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('thunderid-action-revokeOtherSessions')));
      await tester.pumpAndSettle();
      expect(find.text('Revoke other sessions?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('thunderid-action-cancelRevoke')));
      await tester.pumpAndSettle();
      expect(find.text('Revoke other sessions?'), findsNothing);
      expect(log.where((c) => c.method == 'revokeUserSessions'), isEmpty);

      await tester.tap(find.byKey(const Key('thunderid-action-revokeOtherSessions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('thunderid-action-confirmRevoke')));
      await tester.pumpAndSettle();

      expect(log.where((c) => c.method == 'revokeUserSessions').length, 1);
      expect(find.text('Revoke all other sessions'), findsNothing);
    });
  });

  group('platform logos', () {
    test('parses SVG path data, including arcs and compact numbers', () {
      final square = parseSvgPath('M3 3h8.5v8.5H3z').getBounds();
      expect(square, const Rect.fromLTRB(3, 3, 11.5, 11.5));

      // `.5.5` is two numbers, and `-1` starts a new one.
      final compact = parseSvgPath('M0 0l.5.5-1 1').getBounds();
      expect(compact, const Rect.fromLTRB(-0.5, 0, 0.5, 1.5));

      final circle = parseSvgPath('M22 12A10 10 0 1 1 2 12a10 10 0 0 1 20 0z').getBounds();
      expect(circle.left, closeTo(2, 0.01));
      expect(circle.top, closeTo(2, 0.01));
      expect(circle.right, closeTo(22, 0.01));
      expect(circle.bottom, closeTo(22, 0.01));
    });

    test('finds logos for the browsers and systems describeUserAgent names', () {
      for (final browser in ['Chrome', 'Firefox', 'Opera', 'Safari']) {
        expect(browserLogo(browser), isNotNull, reason: browser);
      }
      for (final os in ['iOS', 'macOS', 'Android', 'ChromeOS', 'Windows', 'Linux']) {
        expect(osLogo(os), isNotNull, reason: os);
      }
      expect(browserLogo('Edge'), isNull);
      expect(osLogo(null), isNull);
      for (final logo in [browserLogo('Firefox')!, osLogo('Linux')!]) {
        for (final data in logo.paths) {
          expect(parseSvgPath(data).getBounds().width, greaterThan(18));
        }
      }
    });
  });
}
