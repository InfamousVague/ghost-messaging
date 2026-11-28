import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/account/account_crypto.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/inbox/account_helper.dart';
import 'package:ghost_messaging/inbox/curl_sync.dart';
import 'package:ghost_messaging/inbox/inbox.dart';
import 'package:ghost_messaging/me/me.dart';
import 'package:ghost_messaging/net/carrier.dart';
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/hub_carrier.dart';
import 'package:ghost_relay/handles.dart';
import 'package:ghost_relay/hub.dart';
import 'package:ghost_relay/relay.dart';

/// Me.curlKeep / Me.curlKept against a real relay over a real socket: the relay's `curl-keep` / `curl-kept` answers
/// have to reach the one waiting for them. They didn't (Me._heard had no case for either), so every read timed out,
/// CurlSync.pull swallowed it, and no device ever picked up what the browser extension synced. The other tests of the
/// blob (plugin_sync_test) go through a FakeRelay that never touches Me._heard, so this one goes through the real one.

/// A helper that says it is signed in or not, and takes a sign-in.
class _Helper implements HelperLink {
  _Helper({this.linked = false});
  bool linked;
  final signIns = <Map<String, Object?>>[];

  /// While set, a sign-in is answered with this error; [asked] counts every sign-in asked for, refused or not.
  String? refuse;
  int asked = 0;
  final _out = StreamController<Map<String, Object?>>.broadcast();
  @override
  Stream<Map<String, Object?>> get heard => _out.stream;
  @override
  void say(Map<String, Object?> line) {
    Object? r;
    if (line['op'] == 'unlink') linked = false;
    if (line['op'] == 'status') r = {'linked': linked, 'connected': linked, 'me': 'me-1', 'name': 'Matt', 'handle': 'matt'};
    if (line['op'] == 'sign_in') asked++;
    if (line['op'] == 'sign_in' && refuse != null) {
      final why = refuse;
      scheduleMicrotask(() => _out.add({'id': line['id'], 'ok': false, 'error': why}));
      return;
    }
    if (line['op'] == 'sign_in') {
      signIns.add((line['cookies'] as Map).cast<String, Object?>());
      linked = true;
      r = {'linked': true, 'connected': true, 'me': 'me-1', 'name': 'Matt', 'handle': 'matt'};
    }
    scheduleMicrotask(() => _out.add({'id': line['id'], 'ok': true, 'result': r}));
  }

  @override
  Future<void> close() async {}
}

Future<void> _until(bool Function() done, {String? reason}) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: reason);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Relay relay;
  late int port;
  late Directory dir;
  final words = AccountCrypto.wordsOf(List.filled(16, 3));

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('ghost_messaging/sms'),
      (call) async => call.method == 'secretRead' && (call.arguments as Map)['name'] == 'account_words' ? words.join(' ') : null,
    );
    dir = Directory.systemTemp.createTempSync('curl');
    relay = Relay(hub: Hub(handles: Handles(dataDir: dir, config: const HandlesConfig(publicUrl: 'http://127.0.0.1'))));
    port = await relay.start(port: 0);
  });
  tearDown(() async {
    await relay.stop();
    dir.deleteSync(recursive: true);
  });

  test('a blob kept on the relay is read back by Me, within the wait, by another device of the same identity', () async {
    final keys = NetKeys.generate();
    Future<Me> device() async {
      final hub = HubCarrier(url: 'ws://127.0.0.1:$port/hub', signer: KeysSigner(keys));
      await hub.start();
      await _until(() => hub.state.value == CarrierState.up, reason: hub.problem);
      final me = Me.forTest();
      await me.start(MemoryMeStore(), ChangeNotifier(), () => hub);
      return me;
    }

    // One after the other: both connect with no device name, so the relay treats the second as the first reconnecting.
    final desktop = await device();
    expect(await desktop.curlKept().timeout(const Duration(seconds: 5)), isNull);
    final blob = {
      'v': 1,
      'entries': {
        'discord': {'cookies': {'token': 'x' * 40}, 'at': 1, 'from': 'Chrome'},
      },
    };
    await desktop.curlKeep(blob).timeout(const Duration(seconds: 5));
    final phone = await device();
    expect(await phone.curlKept(strict: true).timeout(const Duration(seconds: 5)), blob);
    // Two readings at one moment both have the answer (GMFB-69): the second took the first's place and the first,
    // the sign-ins' sync, waited out its 25 seconds for nothing.
    final both = await Future.wait([phone.curlKept(), phone.curlKept(strict: true)]).timeout(const Duration(seconds: 5));
    expect(both, [blob, blob]);
  });

  test('a sign-in a device already holds is kept for the account at the next pull, and another device signs in with it; a newer one kept from elsewhere is left alone', () async {
    final keys = NetKeys.generate();
    Future<Me> device() async {
      final hub = HubCarrier(url: 'ws://127.0.0.1:$port/hub', signer: KeysSigner(keys));
      await hub.start();
      await _until(() => hub.state.value == CarrierState.up, reason: hub.problem);
      final me = Me.forTest();
      await me.start(MemoryMeStore(), ChangeNotifier(), () => hub);
      return me;
    }

    Future<(CurlSync, AccountHelper, _Helper)> on(Me me, Directory folder, {bool linked = false, AppState? app}) async {
      final helper = _Helper(linked: linked);
      final n = AccountHelper(discordService, link: () async => helper, folder: folder.path);
      await n.start(AppState());
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      final sync = CurlSync.forTest(networks: () => [n], me: () => me)..app = app ?? AppState();
      addTearDown(() => sync.app = null);
      return (sync, n, helper);
    }

    // The phone was signed in to Discord before sign-ins were shared: only its helper's session.json holds the token.
    final phoneDir = Directory('${dir.path}/phone')..createSync();
    File('${phoneDir.path}/session.json').writeAsStringSync('{"me":"1","token":"phone-token"}');
    final phone = await device();
    final (phoneSync, phoneDiscord, _) = await on(phone, phoneDir, linked: true);
    expect(phoneDiscord.state, InboxState.ready);
    await phoneSync.pull().timeout(const Duration(seconds: 10));
    final kept = await phone.curlKept(strict: true);
    expect(((kept!['entries'] as Map)['discord'] as Map)['cookies'], {'token': 'phone-token'});

    // The desktop, signed out, takes it at its own pull.
    final desk = await device();
    final (deskSync, deskDiscord, deskHelper) = await on(desk, Directory('${dir.path}/desk')..createSync());
    expect(deskDiscord.state, InboxState.signedOut);
    await deskSync.pull().timeout(const Duration(seconds: 15));
    expect(deskHelper.signIns, [
      {'token': 'phone-token'},
    ]);
    expect(deskDiscord.state, InboxState.ready);

    // Another device signs in afresh and keeps its newer token: this one's older sign-in does not write over it.
    final newer = {
      ...kept,
      'entries': {
        'discord': {'cookies': {'token': 'newer-token'}, 'at': DateTime.now().millisecondsSinceEpoch, 'from': 'Laptop'},
      },
    };
    final again = await device();
    await again.curlKeep(newer);
    // This device signed in to it before then (its time known): the other's later sign-in stands.
    final (againSync, _, _) = await on(again, phoneDir, linked: true, app: AppState()..set('curl_mine_discord', '1000')..set('curl_seen_discord', ''));
    await againSync.pull().timeout(const Duration(seconds: 10));
    expect((((await again.curlKept(strict: true))!['entries'] as Map)['discord'] as Map)['cookies'], {'token': 'newer-token'});
  });

  test('a phone hands its paired computer the sign-ins it holds and those the account keeps', () async {
    final keys = NetKeys.generate();
    final hub = HubCarrier(url: 'ws://127.0.0.1:$port/hub', signer: KeysSigner(keys));
    await hub.start();
    await _until(() => hub.state.value == CarrierState.up, reason: hub.problem);
    final phone = Me.forTest();
    await phone.start(MemoryMeStore(), ChangeNotifier(), () => hub);
    await phone.curlKeep({
      'v': 1,
      'entries': {
        'slack': {'cookies': {'d': 'dee', 'token': 'xoxc'}, 'at': 5, 'from': 'Chrome'},
      },
    });
    final folder = Directory('${dir.path}/held')..createSync();
    File('${folder.path}/session.json').writeAsStringSync('{"token":"phone-token"}');
    final n = AccountHelper(discordService, link: () async => _Helper(linked: true), folder: folder.path);
    await n.start(AppState());
    await _until(() => n.state == InboxState.ready);
    final sync = CurlSync.forTest(networks: () => [n], me: () => phone)..app = AppState();
    addTearDown(() => sync.app = null);
    final answer = await sync.forComputer(const {});
    final entries = (answer['entries'] as Map).cast<String, Object?>();
    expect((entries['discord'] as Map)['cookies'], {'token': 'phone-token'});
    expect((entries['slack'] as Map)['cookies'], {'d': 'dee', 'token': 'xoxc'});
  });

  test('a device signed out of a synced sign-in stays out, the same cookies are never tried twice, and a network switched off stays off', () async {
    final keys = NetKeys.generate();
    final hub = HubCarrier(url: 'ws://127.0.0.1:$port/hub', signer: KeysSigner(keys));
    await hub.start();
    await _until(() => hub.state.value == CarrierState.up, reason: hub.problem);
    final me = Me.forTest();
    await me.start(MemoryMeStore(), ChangeNotifier(), () => hub);
    await me.curlKeep({
      'v': 1,
      'entries': {
        'discord': {'cookies': {'token': 'old-token'}, 'at': 0, 'from': 'Phone'},
      },
    });
    final helper = _Helper();
    final n = AccountHelper(discordService, link: () async => helper, folder: (Directory('${dir.path}/d')..createSync()).path);
    final app = AppState();
    await n.start(app);
    await _until(() => n.state == InboxState.signedOut);
    final sync = CurlSync.forTest(networks: () => [n], me: () => me)..app = app;
    addTearDown(() => sync.app = null);

    await sync.pull();
    expect(helper.signIns.length, 1, reason: 'an entry kept with no time is still signed in once');
    await n.signOut();
    expect(n.state, InboxState.signedOut);
    await sync.pull();
    await sync.pull();
    expect(helper.signIns.length, 1, reason: 'signed out here: the same cookies are not signed in again');

    // A sign-in made since, elsewhere, is taken; unless the network is switched off here.
    final fresh = {
      'v': 1,
      'entries': {
        'discord': {'cookies': {'token': 'new-token'}, 'at': DateTime.now().millisecondsSinceEpoch, 'from': 'Laptop'},
      },
    };
    app.set('inbox_on_discord', 'off');
    app.set(Inbox.offByHandKey('discord'), 'hand');
    await me.curlKeep(fresh);
    await sync.pull();
    expect(helper.signIns.length, 1, reason: 'switched off here');
    app.set('inbox_on_discord', 'on');
    app.set(Inbox.offByHandKey('discord'), '');
    await sync.pull();
    expect(helper.signIns.last, {'token': 'new-token'});
  });

  // Matt, 2026-11-28 (GMFB-69): "I'm logged into discord on my phone and other accounts but it's not logging me in on
  // my desktop account". A device settles every network it finds no session of off at its first start, and the sync
  // took that for the person's own switch.
  test('a network the app settled off by itself is signed in with what the account keeps; one the person switched off on another device is not', () async {
    final keys = NetKeys.generate();
    final hub = HubCarrier(url: 'ws://127.0.0.1:$port/hub', signer: KeysSigner(keys));
    await hub.start();
    await _until(() => hub.state.value == CarrierState.up, reason: hub.problem);
    final me = Me.forTest();
    await me.start(MemoryMeStore(), ChangeNotifier(), () => hub);
    await me.curlKeep({
      'v': 1,
      'entries': {
        'discord': {'cookies': {'token': 'phone-token'}, 'at': DateTime.now().millisecondsSinceEpoch, 'from': 'Phone'},
      },
    });
    final helper = _Helper();
    final n = AccountHelper(discordService, link: () async => helper, folder: (Directory('${dir.path}/settled')..createSync()).path);
    final app = AppState();
    await n.start(app);
    await _until(() => n.state == InboxState.signedOut);
    // As the first start leaves it (Inbox._startOne): off, and nobody pressed anything.
    app.set('inbox_on_discord', 'off');
    var elsewhere = true;
    final sync = CurlSync.forTest(networks: () => [n], me: () => me, saidOff: (id) => elsewhere && id == 'netdiscord')..app = app;
    addTearDown(() => sync.app = null);

    await sync.pull();
    expect(helper.signIns, isEmpty, reason: 'switched off by the person on another device: left off');
    elsewhere = false;
    await sync.pull();
    expect(helper.signIns, [{'token': 'phone-token'}], reason: 'off only because the app settled it: signed in');
  });

  // Matt, 2026-11-28: "it's switched on it just says sign in". One try was all a synced sign-in ever got on a device:
  // a failure that had nothing to do with the cookies (no connection that moment) left it at Sign in for good.
  test('a synced sign-in that fails is tried again later, a few times; one a build before this left marked as tried without signing in is tried too', () async {
    final keys = NetKeys.generate();
    final hub = HubCarrier(url: 'ws://127.0.0.1:$port/hub', signer: KeysSigner(keys));
    await hub.start();
    await _until(() => hub.state.value == CarrierState.up, reason: hub.problem);
    final me = Me.forTest();
    await me.start(MemoryMeStore(), ChangeNotifier(), () => hub);
    final at = DateTime.now().millisecondsSinceEpoch;
    await me.curlKeep({
      'v': 1,
      'entries': {
        'discord': {'cookies': {'token': 'phone-token'}, 'at': at, 'from': 'Phone'},
      },
    });
    final helper = _Helper()..refuse = 'no connection';
    final n = AccountHelper(discordService, link: () async => helper, folder: (Directory('${dir.path}/again')..createSync()).path);
    final app = AppState();
    await n.start(app);
    await _until(() => n.state == InboxState.signedOut);
    var clock = at;
    final sync = CurlSync.forTest(networks: () => [n], me: () => me)..app = app..now = () => clock;
    addTearDown(() => sync.app = null);

    await sync.pull();
    expect(helper.asked, 1, reason: 'tried once');
    expect(n.state, InboxState.signedOut);
    await sync.pull();
    expect(helper.asked, 1, reason: 'not again at once');
    clock += const Duration(minutes: 6).inMilliseconds;
    await sync.pull();
    expect(helper.asked, 2, reason: 'again after a few minutes');
    // And it works this time.
    helper.refuse = null;
    clock += const Duration(minutes: 31).inMilliseconds;
    await sync.pull();
    expect(helper.signIns, [{'token': 'phone-token'}]);
    expect(n.state, InboxState.ready);

    // Refused every time: five tries, then no more.
    await n.signOut();
    await me.curlKeep({
      'v': 1,
      'entries': {
        'discord': {'cookies': {'token': 'dead-token'}, 'at': clock, 'from': 'Phone'},
      },
    });
    helper.refuse = 'Discord turned that token away';
    final before = helper.asked;
    for (var i = 0; i < 12; i++) {
      await sync.pull();
      clock += const Duration(days: 1).inMilliseconds;
    }
    expect(helper.asked - before, 5, reason: 'five tries of one sign-in in all');

    // What a build before this left: the cookies marked tried, and never applied, because the try failed.
    final old = AppState();
    final helper2 = _Helper();
    final n2 = AccountHelper(discordService, link: () async => helper2, folder: (Directory('${dir.path}/old')..createSync()).path);
    await n2.start(old);
    await _until(() => n2.state == InboxState.signedOut);
    await me.curlKeep({
      'v': 1,
      'entries': {
        'discord': {'cookies': {'token': 'phone-token'}, 'at': at, 'from': 'Phone'},
      },
    });
    final sync2 = CurlSync.forTest(networks: () => [n2], me: () => me)..app = old;
    addTearDown(() => sync2.app = null);
    old.set('curl_tried_discord', CurlSync.hashForTest({'token': 'phone-token'}));
    await sync2.pull();
    expect(helper2.signIns, [{'token': 'phone-token'}], reason: 'marked tried by an older build, never signed in: tried again');
  });
}
