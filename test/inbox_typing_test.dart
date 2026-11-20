import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/inbox/inbox.dart';
import 'package:ghost_messaging/ui/common.dart' show IconTap;
import 'package:ghost_messaging/ui/inbox_ui.dart';

import 'inbox_screens_test.dart' show FakeNetwork;
import 'support/list_harness.dart';

class _Chat extends FakeNetwork {
  _Chat(List<InboxMessage> history)
    : super('signal', 'Signal', [], {'chat': history});

  int historyReads = 0;

  @override
  List<InboxMessage> shownMessages(String chatId) {
    historyReads++;
    return super.shownMessages(chatId);
  }
}

void main() {
  testWidgets(
    'backspacing to empty keeps focus and restores the composer during rapid edits',
    (tester) async {
      ListPhone([]).install();
      await pumpScreen(
        tester,
        await loadSheet(tester),
        InboxChatScreen(network: _Chat([]), chatId: 'chat'),
        AppState(),
        size: const Size(920, 700),
        platform: 'desktop',
      );
      final field = find.byType(EditableText);
      await tester.showKeyboard(field);
      await settle(tester);
      final editor = tester.state<EditableTextState>(field);
      final emptyRect = tester.getRect(field);

      Future<void> backspace() async {
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();
      }

      Future<void> checkEmpty() async {
        expect(editor.widget.controller.text, isEmpty);
        expect(editor.widget.focusNode.hasFocus, isTrue);
        await tester.pump(const Duration(milliseconds: 16));
        if (defaultTargetPlatform == TargetPlatform.linux) {
          expect(tester.getRect(field), emptyRect);
          expect(find.byKey(const ValueKey('composer-send')), findsNothing);
        }
      }

      for (final pause in [300, 48, 32, 16]) {
        await tester.enterText(field, 'ab');
        await tester.pump();
        await tester.pump(Duration(milliseconds: pause));
        await backspace();
        expect(editor.widget.controller.text, 'a');
        await backspace();
        await checkEmpty();
      }

      await tester.enterText(field, '👍🏽');
      await tester.pump();
      await backspace();
      await checkEmpty();
      const lines = 'prima riga\nseconda riga';
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: lines,
          selection: TextSelection(baseOffset: 0, extentOffset: lines.length),
        ),
      );
      await tester.pump();
      await backspace();
      await checkEmpty();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getRect(field), emptyRect);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.linux,
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'editing a draft updates Send without rebuilding the conversation history',
    (tester) async {
      final date = DateTime(2026);
      final network = _Chat([
        for (var i = 0; i < 2000; i++)
          InboxMessage(
            id: 'm$i',
            text: 'Message $i',
            date: date.add(Duration(minutes: i)),
            mine: i.isEven,
          ),
      ]);
      ListPhone([]).install();
      await pumpScreen(
        tester,
        await loadSheet(tester),
        InboxChatScreen(network: network, chatId: 'chat'),
        AppState(),
        size: const Size(920, 700),
        platform: 'desktop',
      );
      final field = find.byType(EditableText);
      await tester.showKeyboard(field);
      await settle(tester);
      network.historyReads = 0;
      final sendEnabled = <bool>[];
      for (final draft in [' ', ' c', ' ci', ' ciao', '  ', '']) {
        await tester.enterText(field, draft);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        if (draft.isNotEmpty) {
          final send = tester.widget<IconTap>(
            find.byKey(const ValueKey('composer-send')).last,
          );
          sendEnabled.add(send.onPressed != null);
        }
      }
      expect(network.historyReads, 0);
      expect(sendEnabled, [false, true, true, true, false]);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
