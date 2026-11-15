# Ghost Messaging

An SMS and MMS app for Android that replaces the phone's default messaging app, drawn with **Glacier**, the same
UI kit Ghost.md and Ghost Keyboard use.

## Open source, for privacy

Ghost Messaging is open source so anyone can check what it does with their messages.
All of it is here: the phone app, the Mac and Windows apps, the
relay server (`relay/`) that carries messages between your own devices and between friends, the call processing
(`native/voicefx`) and the Google Messages helper (`sidecar/gmessages`, also at
github.com/InfamousVague/ghost-gmessages-sidecar).

- **Licence:** the GNU Affero General Public License v3 (`LICENSE`). Anyone who runs a changed copy, the relay
  included, for others to use owes those people its source.
- **What is not here:** the keys releases are signed with (Android's and Apple's), and the server's own credentials
  (Twilio and the like, read from its environment). Builds made from this source are not signed as the releases are,
  so they install as a separate app.
- **Third-party parts** keep their own licences: the emoji fonts (`assets/emoji/LICENSES.md`), Inter and JetBrains
  Mono (`assets/fonts/OFL.txt`), RNNoise (`native/voicefx/rnnoise/COPYING`, BSD), DeepFilterNet (MIT or Apache-2.0)
  and mautrix-gmessages' libgm (AGPL-3.0).

  
## How it is built

| Part | Where | What |
| --- | --- | --- |
| The screens | `lib/` | Flutter, drawn with Glacier (`packages/glacier`, copied from Ghost Keyboard's copy of Ghost.md's kit: `packages/glacier/VENDORED.md`), Ghost.md's stylesheets (`assets/css`), Ghost Keyboard's settings kit (`lib/kit`) and Lucide icons drawn as Ghost.md draws them (`lib/art`). |
| The bridge | `lib/sms.dart` and `MainActivity.kt` | `ghost_messaging/sms` (calls) and `ghost_messaging/events` (a conversation changed; a notification asked for one). |
| The messages | `Store.kt` | Android's SMS/MMS provider: conversations, messages, parts, contacts, and writing what arrives or is sent. |
| Sending and receiving | `Messaging.kt` | `SmsManager` for SMS and MMS, and the receivers Android requires of a default SMS app (`SMS_DELIVER`, `WAP_PUSH_DELIVER`). |
| MMS bytes | `Pdu.kt` | The MMS wire format, reading m-notification-ind and m-retrieve-conf and writing m-send-req and m-notifyresp-ind. Android does the radio and the carrier's HTTP but leaves the bytes to the app. Tests: `android/app/src/test/.../PduTest.kt`. |
| Notifications | `Notifier.kt` | Notifications with Reply and Mark as read, the "respond via message" service, and the file provider Android's MMS service reads and writes through. |
| Paired computers, on the phone | `Desk.kt`, `DeskService.kt`, `DeskSession.kt`, `DeskCrypto.kt`, `WsClient.kt`, `ScanActivity.kt` | Who is paired and each one's key (under an Android Keystore key), the foreground service that listens on the local network (NSD) and dials the relay, one connection as the phone answers it, the sealing, a WebSocket client written out, and the QR scanner (Camera2 and ZXing). Tests: `DeskCryptoTest`, `DeskSessionTest`, `WsClientTest`, `ScanTest`. |
| The Mac app | `macos/`, `lib/desktop/` | The same Flutter project with a macOS runner: `lib/main.dart` goes to `lib/desktop/main.dart` on a computer. `link/` is the sealing (pointycastle), a connection, the relay's socket and `PhoneLink` (pairing, local first, the relay when it fails); `remote.dart` answers the phone's screens' calls from the phone; `ui/` is the wizard, the two panes and Settings; `macos/Runner/DeskChannels.swift` is Bonjour, the Keychain and the Mac's name. |
| Plugins | `lib/plugins/` | The contract (`plugin.dart`), the registry and the plugins the app ships with (`registry.dart`), the conversations' tags (`tag_store.dart`), what the list of conversations keeps of them (`list.dart`), what a conversation would ask (`conversation.dart`), what is drawn of them (`ui.dart`), Settings › Plugins (`settings.dart`), and the plugins themselves (`codes.dart`, `kinds.dart`, `spam.dart`, `embeds.dart`, `actions.dart`, `replies.dart`, `day.dart`, `quiet.dart`, `strangers.dart`). |
| The relay | `relay/` | A WebSocket server in Dart's own library alone (`relay/README.md`). Not on a server. |

## Building

```sh
flutter pub get
flutter build apk --release --target-platform android-arm64   # build/app/outputs/flutter-apk/app-release.apk
flutter test                                                  # reactions, edits, effects, emoji sets, settings and backgrounds; builds every screen;
                                                              # the Mac's sealing and its link to a stand-in phone through the real relay
flutter test --update-goldens test/screens_test.dart          # every screen, light and dark, written to test/shots/
flutter test --update-goldens test/desk_screens_test.dart     # the Mac's screens, written to test/shots/mac-*
cd android && ./gradlew :app:testDebugUnitTest                # the MMS encoder and decoder, the encryption, a background as a text, the codes offered,
                                                              # the sealing with a computer, a computer's connection, the WebSocket client, a QR code read
flutter build macos                                           # the Mac app: build/macos/Build/Products/Release/Ghost Messaging.app
(cd relay && dart test && dart run bin/relay.dart)            # the relay: its tests, then ws://127.0.0.1:8787
flutter test integration_test/desk_live_test.dart -d macos    # the real Mac app against the phone app on an emulator (the file says how)
```

`flutter build apk` builds the phone app exactly as before: the Mac app is the same project's other platform, and
nothing of it is in the APK but the Settings page and the phone's half (`Desk*.kt`).

The emoji sets' picture (`test/shots/7-emoji-sets.png`) is compared on Linux only: a Mac's test engine draws fonts
with Core Text, which leaves Twemoji's row blank, where Linux's and Android's draw it with FreeType.
