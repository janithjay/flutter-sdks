// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import '../i18n/thunderid_i18n.dart';
import '../models/sso_session.dart';
import '../models/thunderid_error.dart';
import 'internal/account_style.dart';
import 'internal/platform_logos.dart';
import 'thunderid_provider.dart';

/// The browser, operating system and device model a User-Agent names, and whether it came from a
/// native app rather than a browser. A part the string doesn't reveal is null.
class UserAgentDescription {
  final String? browser;
  final String? os;
  final String? device;
  final bool isApp;

  const UserAgentDescription({this.browser, this.os, this.device, this.isApp = false});

  @override
  bool operator ==(Object other) =>
      other is UserAgentDescription &&
      other.browser == browser &&
      other.os == os &&
      other.device == device &&
      other.isApp == isApp;

  @override
  int get hashCode => Object.hash(browser, os, device, isApp);

  @override
  String toString() => 'UserAgentDescription(browser: $browser, os: $os, device: $device, isApp: $isApp)';
}

// The User-Agent the mobile SDKs send: `ThunderID-Android/1.4.0 (Android 14; Google Pixel 8)`, or the
// iOS equivalent. This SDK bridges to those, so its requests carry the same header. The first word
// of the comment is the operating system, the part after `;` the device.
final _nativeSdkPattern = RegExp(r'\bThunderID-(?:Android|iOS)/\S*\s*\((\w+)[^;)]*(?:;\s*([^)]+))?\)');

// Checked in order, matching the JavaScript SDK's describeUserAgent: several browsers also carry the
// tokens of the ones they derive from, so Edge, Opera and Samsung Internet come before Chrome, and
// Chrome before Safari.
final _browserPatterns = <(RegExp, String)>[
  (RegExp(r'\bEdg(?:e|A|iOS)?/'), 'Edge'),
  (RegExp(r'\b(?:OPR|Opera)/'), 'Opera'),
  (RegExp(r'\bSamsungBrowser/'), 'Samsung Internet'),
  (RegExp(r'\b(?:Firefox|FxiOS)/'), 'Firefox'),
  (RegExp(r'\b(?:Chrome|CriOS)/'), 'Chrome'),
  (RegExp(r'\bVersion/[\d.]+.*\bSafari/'), 'Safari'),
];

final _osPatterns = <(RegExp, String)>[
  (RegExp(r'\bWindows\b'), 'Windows'),
  (RegExp(r'\b(?:iPhone|iPad|iPod)\b'), 'iOS'),
  (RegExp(r'\bAndroid\b'), 'Android'),
  (RegExp(r'\bCrOS\b'), 'ChromeOS'),
  (RegExp(r'\bMac OS X\b|\bMacintosh\b'), 'macOS'),
  (RegExp(r'\bLinux\b'), 'Linux'),
];

/// Reads the browser and operating system from a User-Agent, or the device from a mobile SDK's, for
/// showing a session as, for example, "Chrome on macOS". It recognizes the common browsers only, and
/// is for display, never for decisions.
UserAgentDescription describeUserAgent(String? userAgent) {
  if (userAgent == null || userAgent.isEmpty) return const UserAgentDescription();
  final native = _nativeSdkPattern.firstMatch(userAgent);
  if (native != null) {
    final device = native.group(2)?.trim();
    return UserAgentDescription(
      os: native.group(1),
      device: device == null || device.isEmpty ? null : device,
      isApp: true,
    );
  }
  String? firstMatch(List<(RegExp, String)> patterns) {
    for (final (pattern, name) in patterns) {
      if (pattern.hasMatch(userAgent)) return name;
    }
    return null;
  }

  return UserAgentDescription(browser: firstMatch(_browserPatterns), os: firstMatch(_osPatterns));
}

/// Sessions that share an operating system, listed together.
class SessionGroup {
  final String? os;
  final List<SSOSession> sessions;

  const SessionGroup(this.os, this.sessions);

  bool get hasCurrent => sessions.any((s) => s.isCurrent);
}

/// Groups sessions by the operating system their User-Agent names. The group holding the current
/// session comes first; the rest keep the server's order, most recently active first.
List<SessionGroup> groupSessionsByOs(List<SSOSession> sessions) {
  final grouped = <String?, List<SSOSession>>{};
  for (final session in sessions) {
    grouped.putIfAbsent(describeUserAgent(session.userAgent).os, () => []).add(session);
  }
  final groups = grouped.entries.map((e) => SessionGroup(e.key, e.value)).toList();
  return [...groups.where((g) => g.hasCurrent), ...groups.where((g) => !g.hasCurrent)];
}

/// Resolves an active-sessions key and substitutes `{name}` placeholders in one call.
String translateSessions(ThunderIDI18n i18n, String key, [Map<String, Object> values = const {}]) =>
    values.entries.fold(
      i18n.resolve('activeSessions.$key'),
      (text, entry) => text.replaceAll('{${entry.key}}', entry.value.toString()),
    );

// The server lists participants first joined first, so the first started the session.
String? _startingAppName(SSOSession session) =>
    session.participants.isEmpty ? null : session.participants.first.appName;

/// "Chrome on macOS", a native app's device ("Redmi Note 8 Pro"), or the part that is known, or "Unknown device".
String deviceLabel(SSOSession session, ThunderIDI18n i18n) {
  final description = describeUserAgent(session.userAgent);
  // A native app's session is named by its device alone; its applications are listed separately.
  final device = description.device;
  if (device != null) return device;
  final client = description.browser ?? _startingAppName(session);
  final place = description.os;
  if (client != null && place != null) {
    return translateSessions(i18n, 'device', {'client': client, 'place': place});
  }
  return client ?? place ?? translateSessions(i18n, 'unknownDevice');
}

/// The address the session was last seen from, falling back to the one it was created from.
String? sessionIp(SSOSession session) => session.lastActiveIp ?? session.creationIp;

/// Whether a revoke failed only because the session is already gone, revoked elsewhere or expired.
bool isAlreadyRevoked(Object error) => error is IAMException && error.code == ThunderIDErrorCode.notFound;

/// State handed to [BaseActiveSessions]'s builder.
///
/// Reads live off its owning state through getters, and [changes] notifies on every update, so a
/// page pushed with `Navigator.push`, which its owner's rebuilds never reach, can follow along.
class ActiveSessionsState {
  final _BaseActiveSessionsState _owner;

  const ActiveSessionsState._(this._owner);

  List<SSOSession> get sessions => _owner._sessions;
  int get totalCount => _owner._totalCount;
  bool get isLoading => _owner._loading;
  String? get error => _owner._error;
  String? get revokingSessionId => _owner._revokingSessionId;
  bool get revokingOthers => _owner._revokingOthers;
  Listenable get changes => _owner._changes;

  List<SessionGroup> get groups => groupSessionsByOs(sessions);

  /// Sessions other than the current one, counted across every page, not just the loaded one.
  int get otherCount {
    final others = totalCount - sessions.where((s) => s.isCurrent).length;
    return others < 0 ? 0 : others;
  }

  Future<void> refresh() => _owner._load();
  Future<void> revoke(String sessionId) => _owner._revoke(sessionId);
  Future<void> revokeOthers() => _owner._revokeOthers();
}

/// Headless active-sessions list (unstyled variant). Loads the signed-in user's live SSO sessions
/// from `GET /sessions/me`, revokes one or every other session, and hands its [ActiveSessionsState]
/// to [builder], mirroring the [BaseUserProfile] split.
///
/// Only the first page is loaded, [limit] sessions at most (the server's page size by default);
/// sessions beyond it can still be revoked with [ActiveSessionsState.revokeOthers].
class BaseActiveSessions extends StatefulWidget {
  final int? limit;
  final VoidCallback? onRevoked;
  final VoidCallback? onError;
  final Widget Function(BuildContext context, ActiveSessionsState state) builder;

  const BaseActiveSessions({
    super.key,
    this.limit,
    this.onRevoked,
    this.onError,
    required this.builder,
  });

  @override
  State<BaseActiveSessions> createState() => _BaseActiveSessionsState();
}

class _BaseActiveSessionsState extends State<BaseActiveSessions> {
  List<SSOSession> _sessions = const [];
  int _totalCount = 0;
  bool _loading = false;
  String? _error;
  String? _revokingSessionId;
  bool _revokingOthers = false;
  final _changes = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _changes.dispose();
    super.dispose();
  }

  void _update(VoidCallback change) {
    if (!mounted) return;
    setState(change);
    _changes.value++;
  }

  Future<void> _load() async {
    if (!mounted) return;
    final thunder = ThunderIDProvider.of(context);
    _update(() => _loading = true);
    try {
      final page = await thunder.client.getUserSessions(limit: widget.limit);
      _update(() {
        _sessions = page.sessions;
        _totalCount = page.totalResults;
        _error = null;
      });
    } catch (_) {
      _update(() => _error = translateSessions(thunder.i18n, 'error.load'));
      widget.onError?.call();
    } finally {
      _update(() => _loading = false);
    }
  }

  Future<void> _runRevoke(Future<void> Function() call) async {
    final i18n = ThunderIDProvider.of(context).i18n;
    _update(() => _error = null);
    try {
      await call();
      await _load();
      widget.onRevoked?.call();
    } catch (e) {
      if (isAlreadyRevoked(e)) {
        await _load();
      } else {
        _update(() => _error = translateSessions(i18n, 'error.revoke'));
        widget.onError?.call();
      }
    }
  }

  Future<void> _revoke(String sessionId) async {
    if (_revokingSessionId != null || _revokingOthers) return;
    final client = ThunderIDProvider.of(context).client;
    _update(() => _revokingSessionId = sessionId);
    try {
      await _runRevoke(() => client.revokeUserSession(sessionId));
    } finally {
      _update(() => _revokingSessionId = null);
    }
  }

  Future<void> _revokeOthers() async {
    if (_revokingSessionId != null || _revokingOthers) return;
    final client = ThunderIDProvider.of(context).client;
    _update(() => _revokingOthers = true);
    try {
      await _runRevoke(() => client.revokeUserSessions(exceptCurrent: true));
    } finally {
      _update(() => _revokingOthers = false);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, ActiveSessionsState._(this));
}

/// Styled active-sessions list. Renders one row per operating system and a Manage sessions row,
/// that open a full-screen list of every session. A session opens a detail page, where it can be
/// signed out after a confirmation, matching [ChangeCredential]'s row-then-editor structure.
///
/// The current session has no Revoke action, since ending it would also end the session the app
/// is using. Use the regular sign-out for that.
///
/// [title] overrides the "Active sessions" heading; pass an empty string to omit it.
class ActiveSessions extends StatelessWidget {
  final int? limit;
  final String? title;
  final VoidCallback? onRevoked;

  const ActiveSessions({super.key, this.limit, this.title, this.onRevoked});

  @override
  Widget build(BuildContext context) {
    final i18n = ThunderIDProvider.of(context).i18n;
    return BaseActiveSessions(
      limit: limit,
      onRevoked: onRevoked,
      builder: (context, state) => _ActiveSessionsSummary(
        state: state,
        i18n: i18n,
        title: title ?? translateSessions(i18n, 'section'),
      ),
    );
  }
}

class _ActiveSessionsSummary extends StatelessWidget {
  final ActiveSessionsState state;
  final ThunderIDI18n i18n;
  final String title;

  const _ActiveSessionsSummary({required this.state, required this.i18n, required this.title});

  void _openList(BuildContext context) => _pushPage(
        context,
        _SessionListPage(
          state: state,
          i18n: i18n,
          backLabel: title.isEmpty ? translateSessions(i18n, 'section') : title,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final colors = ThunderAccountColors.of(context);
    final children = <Widget>[];
    if (title.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: colors.text)),
        ),
      );
    }
    if (state.isLoading && state.sessions.isEmpty) {
      children.add(Text(translateSessions(i18n, 'loading'), style: TextStyle(color: colors.textSecondary)));
    } else if (state.sessions.isEmpty) {
      children.add(
        Text(
          state.error ?? translateSessions(i18n, 'empty'),
          style: TextStyle(fontSize: 13, color: state.error == null ? colors.textSecondary : colors.error),
        ),
      );
    } else {
      for (final group in state.groups) {
        children.add(
          _NavRow(
            leading: _OsLogo(os: group.os, size: 22),
            label: _groupTitle(i18n, group),
            onTap: () => _openList(context),
          ),
        );
      }
      children.add(
        _NavRow(
          leading: Icon(Icons.tune, size: 22, color: colors.accent),
          label: translateSessions(i18n, 'manage'),
          accent: true,
          identifier: 'thunderid-action-manageSessions',
          onTap: () => _openList(context),
        ),
      );
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(translateSessions(i18n, 'footnote'), style: TextStyle(fontSize: 13, color: colors.textSecondary)),
        ),
      );
      if (state.error != null) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(state.error!, style: TextStyle(fontSize: 13, color: colors.error)),
          ),
        );
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

String _groupTitle(ThunderIDI18n i18n, SessionGroup group) {
  final os = group.os ?? translateSessions(i18n, 'unknownDevice');
  return group.sessions.length == 1
      ? translateSessions(i18n, 'group.one', {'os': os})
      : translateSessions(i18n, 'group.other', {'count': group.sessions.length, 'os': os});
}

class _NavRow extends StatelessWidget {
  final Widget leading;
  final String label;
  final VoidCallback onTap;
  final bool accent;
  final String? identifier;

  const _NavRow({
    required this.leading,
    required this.label,
    required this.onTap,
    this.accent = false,
    this.identifier,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ThunderAccountColors.of(context);
    final row = InkWell(
      key: identifier != null ? Key(identifier!) : null,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.divider))),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 16),
            Expanded(
              child: Text(label, style: TextStyle(fontSize: 16, color: accent ? colors.accent : colors.text)),
            ),
            Icon(Icons.chevron_right, size: 20, color: colors.textSecondary),
          ],
        ),
      ),
    );
    return identifier == null ? row : Semantics(identifier: identifier, button: true, child: row);
  }
}

/// Pushes a sessions page with the same fade [UserProfile] and [ChangeCredential] open their
/// edit pages with.
void _pushPage(BuildContext context, Widget page) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
      pageBuilder: (context, animation, secondaryAnimation) => page,
    ),
  );
}

/// A pushed sessions page, laid out like [ThunderAccountEditPage]: the back link, then the page's
/// content, refreshed by pulling down.
class _SessionsPage extends StatelessWidget {
  final String backLabel;
  final ActiveSessionsState state;
  final List<Widget> Function(BuildContext context) children;

  const _SessionsPage({required this.backLabel, required this.state, required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = ThunderAccountColors.of(context);
    // Scaffold rather than a bare Material: a PageRouteBuilder, unlike MaterialPageRoute, gives
    // its page no Material ancestor, and InkWell needs one.
    return Scaffold(
      backgroundColor: colors.pageBackground,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state.changes,
          builder: (context, _) => RefreshIndicator(
            onRefresh: state.refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: ThunderAccountBackLink(label: backLabel, onTap: () => Navigator.of(context).maybePop()),
                ),
                ...children(context),
                if (state.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(state.error!, style: TextStyle(fontSize: 13, color: colors.error)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Every session, grouped by operating system, with Revoke all other sessions at the end.
class _SessionListPage extends StatelessWidget {
  final ActiveSessionsState state;
  final ThunderIDI18n i18n;
  final String backLabel;

  const _SessionListPage({required this.state, required this.i18n, required this.backLabel});

  Future<void> _confirmOthers(BuildContext context) async {
    final count = state.otherCount;
    final confirmed = await _confirmRevokeDialog(
      context,
      i18n,
      title: translateSessions(i18n, 'confirm.others.title'),
      message: count == 1
          ? translateSessions(i18n, 'confirm.others.body.one')
          : translateSessions(i18n, 'confirm.others.body.other', {'count': count}),
    );
    if (confirmed) await state.revokeOthers();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ThunderAccountColors.of(context);
    return _SessionsPage(
      backLabel: backLabel,
      state: state,
      children: (context) => [
        const SizedBox(height: 4),
        Text(
          translateSessions(i18n, 'title'),
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: colors.text),
        ),
        for (final group in state.groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 4),
            child: Row(
              children: [
                _OsLogo(os: group.os, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _groupTitle(i18n, group).toUpperCase(),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          for (final session in group.sessions)
            _SessionRow(
              session: session,
              i18n: i18n,
              onTap: () => _pushPage(
                context,
                _SessionDetailPage(sessionId: session.id, state: state, i18n: i18n),
              ),
            ),
        ],
        if (state.otherCount > 0 && state.sessions.any((s) => s.isCurrent)) ...[
          const SizedBox(height: 28),
          _DangerButton(
            label: translateSessions(i18n, 'revokeOthers'),
            identifier: 'thunderid-action-revokeOtherSessions',
            busy: state.revokingOthers,
            onPressed: state.revokingOthers || state.revokingSessionId != null ? null : () => _confirmOthers(context),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              translateSessions(i18n, 'revokeOthers.note'),
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
          ),
        ],
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  final SSOSession session;
  final ThunderIDI18n i18n;
  final VoidCallback onTap;

  const _SessionRow({required this.session, required this.i18n, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = ThunderAccountColors.of(context);
    final apps = session.participants.map((p) => p.appName).whereType<String>().join(', ');
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.divider))),
        child: Row(
          children: [
            _ClientTile(description: describeUserAgent(session.userAgent)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(deviceLabel(session, i18n), style: TextStyle(fontSize: 16, color: colors.text)),
                      if (session.isCurrent) _CurrentChip(i18n: i18n),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    translateSessions(
                      i18n,
                      'lastActive.since',
                      {'date': formatSessionTime(context, session.lastActiveAt)},
                    ),
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  ),
                  if (apps.isNotEmpty) Text(apps, style: TextStyle(fontSize: 13, color: colors.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// One session's details. A session other than the current one can be signed out from here; the
/// page closes when it drops out of the reloaded list.
class _SessionDetailPage extends StatefulWidget {
  final String sessionId;
  final ActiveSessionsState state;
  final ThunderIDI18n i18n;

  const _SessionDetailPage({required this.sessionId, required this.state, required this.i18n});

  @override
  State<_SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<_SessionDetailPage> {
  @override
  void initState() {
    super.initState();
    widget.state.changes.addListener(_closeWhenGone);
  }

  @override
  void dispose() {
    widget.state.changes.removeListener(_closeWhenGone);
    super.dispose();
  }

  void _closeWhenGone() {
    final gone = !widget.state.isLoading && !widget.state.sessions.any((s) => s.id == widget.sessionId);
    if (gone && mounted) Navigator.of(context).maybePop();
  }

  Future<void> _confirmRevoke(BuildContext context, SSOSession session) async {
    final i18n = widget.i18n;
    final confirmed = await _confirmRevokeDialog(
      context,
      i18n,
      title: translateSessions(i18n, 'confirm.one.title'),
      message: translateSessions(i18n, 'confirm.one.body', {'device': deviceLabel(session, i18n)}),
    );
    if (confirmed) await widget.state.revoke(session.id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ThunderAccountColors.of(context);
    final i18n = widget.i18n;
    final state = widget.state;
    return _SessionsPage(
      backLabel: translateSessions(i18n, 'title'),
      state: state,
      children: (context) {
        final matches = state.sessions.where((s) => s.id == widget.sessionId);
        if (matches.isEmpty) return const [];
        final session = matches.first;
        final description = describeUserAgent(session.userAgent);
        final unknown = translateSessions(i18n, 'unknown');
        final apps = session.participants.map((p) => p.appName ?? unknown).join(', ');
        final subtitle =
            [description.os, if (session.isCurrent) translateSessions(i18n, 'current')].whereType<String>().join(' · ');
        return [
          const SizedBox(height: 12),
          Center(
            child: Column(
              children: [
                _SessionBadge(description: description),
                const SizedBox(height: 12),
                Text(
                  deviceLabel(session, i18n),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colors.text),
                ),
                if (subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle, style: TextStyle(fontSize: 13, color: colors.textSecondary)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _DetailRow(label: translateSessions(i18n, 'ip'), value: sessionIp(session) ?? unknown, monospace: true),
          _DetailRow(
            label: translateSessions(i18n, 'signedIn'),
            value: formatSessionTime(context, session.authenticatedAt),
          ),
          _DetailRow(
            label: translateSessions(i18n, 'lastActive'),
            value: formatSessionTime(context, session.lastActiveAt),
          ),
          _DetailRow(
            label: translateSessions(i18n, 'applications'),
            value: apps.isEmpty ? unknown : apps,
            showDivider: false,
          ),
          const SizedBox(height: 24),
          if (session.isCurrent)
            Text(translateSessions(i18n, 'current.note'), style: TextStyle(fontSize: 13, color: colors.textSecondary))
          else
            _DangerButton(
              label: translateSessions(i18n, 'revoke'),
              identifier: 'thunderid-action-revokeSession',
              busy: state.revokingSessionId == session.id,
              onPressed: state.revokingSessionId != null || state.revokingOthers
                  ? null
                  : () => _confirmRevoke(context, session),
            ),
        ];
      },
    );
  }
}

/// A label above its value with a bottom divider, the same as [ThunderAccountRow] without the
/// edit link. The value can be selected and copied.
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool monospace;
  final bool showDivider;

  const _DetailRow({required this.label, required this.value, this.monospace = false, this.showDivider = true});

  @override
  Widget build(BuildContext context) {
    final colors = ThunderAccountColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        border: showDivider ? Border(bottom: BorderSide(color: colors.divider)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 15, color: colors.textSecondary)),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: TextStyle(fontSize: 16, color: colors.text, fontFamily: monospace ? 'monospace' : null),
          ),
        ],
      ),
    );
  }
}

class _CurrentChip extends StatelessWidget {
  final ThunderIDI18n i18n;

  const _CurrentChip({required this.i18n});

  @override
  Widget build(BuildContext context) {
    final colors = ThunderAccountColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: colors.pillBackground, borderRadius: BorderRadius.circular(10)),
      child: Text(
        translateSessions(i18n, 'current'),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.pillText),
      ),
    );
  }
}

/// A full-width outlined button in the error color, sized like [ThunderOutlineButton].
class _DangerButton extends StatelessWidget {
  final String label;
  final String identifier;
  final bool busy;
  final VoidCallback? onPressed;

  const _DangerButton({required this.label, required this.identifier, required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = ThunderAccountColors.of(context);
    return Semantics(
      identifier: identifier,
      button: true,
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: OutlinedButton(
          key: Key(identifier),
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.error,
            side: BorderSide(color: colors.error, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: busy
              ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: colors.error))
              : Text(label, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

Future<bool> _confirmRevokeDialog(
  BuildContext context,
  ThunderIDI18n i18n, {
  required String title,
  required String message,
}) =>
    showThunderAccountConfirmation(
      context,
      title: title,
      message: message,
      cancelLabel: translateSessions(i18n, 'cancel'),
      confirmLabel: translateSessions(i18n, 'revoke'),
      cancelIdentifier: 'thunderid-action-cancelRevoke',
      confirmIdentifier: 'thunderid-action-confirmRevoke',
      destructive: true,
    );

/// The operating system's logo, or a generic device icon for one without a logo.
class _OsLogo extends StatelessWidget {
  final String? os;
  final double size;

  const _OsLogo({required this.os, required this.size});

  @override
  Widget build(BuildContext context) {
    final colors = ThunderAccountColors.of(context);
    final logo = osLogo(os);
    return logo == null
        ? Icon(Icons.devices_other, size: size, color: colors.textSecondary)
        : PlatformLogoView(logo: logo, size: size, fallbackColor: colors.text);
  }
}

/// The browser's logo, or an icon for a native app or a browser without a logo.
class _ClientLogo extends StatelessWidget {
  final UserAgentDescription description;
  final double size;

  const _ClientLogo({required this.description, required this.size});

  @override
  Widget build(BuildContext context) {
    final colors = ThunderAccountColors.of(context);
    final logo = browserLogo(description.browser);
    if (logo != null) return PlatformLogoView(logo: logo, size: size, fallbackColor: colors.text);
    final icon = description.browser == null && description.isApp
        ? Icons.smartphone
        : description.browser == null
            ? Icons.computer
            : Icons.language;
    return Icon(icon, size: size, color: colors.textSecondary);
  }
}

/// The client's logo on a bordered tile, leading a session row. Brand colors stay readable on its
/// white fill in dark mode too.
class _ClientTile extends StatelessWidget {
  final UserAgentDescription description;

  const _ClientTile({required this.description});

  @override
  Widget build(BuildContext context) {
    final colors = ThunderAccountColors.of(context);
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ThunderAccountColors.light.pageBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.divider),
      ),
      child: MediaQuery(
        // The tile is always white, so draw an uncolored logo (Apple, Linux) as on a light page.
        data: MediaQuery.of(context).copyWith(platformBrightness: Brightness.light),
        child: _ClientLogo(description: description, size: 20),
      ),
    );
  }
}

/// The operating system in a circle with the client badged on its corner, like
/// [ThunderAccountAvatar]'s camera badge, heading a session's detail page.
class _SessionBadge extends StatelessWidget {
  final UserAgentDescription description;

  const _SessionBadge({required this.description});

  @override
  Widget build(BuildContext context) {
    final colors = ThunderAccountColors.of(context);
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 80,
            height: 80,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: colors.divider),
            child: _OsLogo(os: description.os, size: 40),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ThunderAccountColors.light.pageBackground,
                border: Border.all(color: colors.pageBackground, width: 2),
              ),
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(platformBrightness: Brightness.light),
                child: _ClientLogo(description: description, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Formats a server timestamp as a medium date and time in the device's locale, or returns it
/// unchanged when it can't be read.
String formatSessionTime(BuildContext context, String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  final local = parsed.toLocal();
  final localizations = MaterialLocalizations.of(context);
  final time = localizations.formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
    alwaysUse24HourFormat: MediaQuery.maybeOf(context)?.alwaysUse24HourFormat ?? false,
  );
  return '${localizations.formatMediumDate(local)}, $time';
}
