import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:fourier/http/init.dart';
import 'package:fourier/models/feed.dart';
import 'package:fourier/pages/main/widgets/macos_sidebar.dart';
import 'package:fourier/pages/subscriptions/subscriptions_controller.dart';
import 'package:fourier/pages/timeline/timeline_controller.dart';
import 'package:fourier/services/feed_silent_settings_service.dart';

import 'support/hive_test_helper.dart';

class _Timeline extends TimelineController {
  @override
  // ignore: must_call_super
  void onInit() {} // No startup requests in a sidebar interaction test.
}

class _Subscriptions extends SubscriptionsController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _Harness {
  _Harness(this.timeline, this.subscriptions, this.group, this.page);
  final TimelineController timeline;
  final SubscriptionsController subscriptions;
  final SilentFeedGroup group;
  final ValueNotifier<int> page;
}

Future<_Harness> _pumpSidebar(
  WidgetTester tester, {
  FocusNode? inputFocus,
}) async {
  final group = (await tester.runAsync(() async {
    final group = await FeedSilentSettingsService.createGroup(
      'Silent category',
    );
    await FeedSilentSettingsService.setSilent(
      'silent-feed',
      true,
      groupId: group.id,
    );
    return group;
  }))!;
  final timeline = Get.put<TimelineController>(_Timeline());
  final subscriptions = Get.put<SubscriptionsController>(_Subscriptions());
  subscriptions.loadingState.value = const Success<List<SourceViewNode>>([]);
  subscriptions.viewNodes.assignAll([
    SourceViewNode(
      view: 0,
      name: 'Articles',
      categories: [
        SourceCategoryNode(
          name: 'Normal category',
          feeds: [
            FeedModel(feedId: 'normal-feed', title: 'Normal feed'),
            FeedModel(feedId: 'silent-feed', title: 'Silent feed'),
          ],
        ),
      ],
    ),
  ]);
  subscriptions.setExpanded('cat:Articles:Normal category', true);
  subscriptions.setExpanded('silent-group:${group.id}', true);
  final page = ValueNotifier(0);
  addTearDown(page.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.macOS),
      home: Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: macOSSidebarExpandedWidth,
              child: ValueListenableBuilder<int>(
                valueListenable: page,
                builder: (_, index, _) => MacOSSidebar(
                  currentIndex: index,
                  onIndexChanged: (index) => page.value = index,
                ),
              ),
            ),
            if (inputFocus != null)
              Expanded(child: TextField(focusNode: inputFocus)),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(timeline, subscriptions, group, page);
}

FocusNode _focus(WidgetTester tester, String label) =>
    Focus.of(tester.element(find.text(label)));

bool _selected(WidgetTester tester, String label) =>
    tester
        .widget<Material>(
          find
              .ancestor(of: find.text(label), matching: find.byType(Material))
              .first,
        )
        .color !=
    Colors.transparent;

Future<void> _focusLabel(WidgetTester tester, String label) async {
  _focus(tester, label).requestFocus();
  await tester.pumpAndSettle();
}

void main() {
  late FocusHighlightStrategy strategy;
  setUp(() async {
    await HiveTestHelper.setUp();
    Get.testMode = true;
    strategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  });
  tearDown(() async {
    FocusManager.instance.highlightStrategy = strategy;
    Get.reset();
    await HiveTestHelper.tearDown();
  });

  testWidgets(
    'clicking a silent category removes All focus and selects only that category',
    (tester) async {
      final harness = await _pumpSidebar(tester);
      await _focusLabel(tester, '全部文章');
      await tester.tap(find.text('Silent category'));
      await tester.pumpAndSettle();
      expect(harness.timeline.selectedSilentGroupId.value, harness.group.id);
      expect(harness.timeline.isSilentSelected.value, true);
      expect(_selected(tester, '全部文章'), false);
      expect(_selected(tester, 'Silent category'), true);
      expect(_focus(tester, '全部文章').hasFocus, false);
      expect(_focus(tester, 'Silent category').hasPrimaryFocus, true);
    },
  );

  testWidgets(
    'normal categories and individual normal or silent feeds transfer focus',
    (tester) async {
      final harness = await _pumpSidebar(tester);
      var previous = '全部文章';
      await _focusLabel(tester, previous);
      for (final label in [
        'Normal category',
        'Normal feed',
        'Silent feed',
        '全部文章',
      ]) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(_focus(tester, previous).hasFocus, false);
        expect(_focus(tester, label).hasPrimaryFocus, true);
        expect(_selected(tester, label), true);
        previous = label;
      }
      expect(harness.timeline.isSilentSelected.value, false);
      expect(harness.timeline.selectedFeedId.value, isNull);
    },
  );

  testWidgets(
    'page destinations transfer focus away from the old navigation entry',
    (tester) async {
      final harness = await _pumpSidebar(tester);
      await _focusLabel(tester, '全部文章');
      var previous = '全部文章';
      for (final entry in {'垃圾拦截': 1, '最近阅读': 2, '设置': 3}.entries) {
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        expect(harness.page.value, entry.value);
        expect(_focus(tester, previous).hasFocus, false);
        expect(_focus(tester, entry.key).hasPrimaryFocus, true);
        expect(_selected(tester, entry.key), true);
        previous = entry.key;
      }
    },
  );

  testWidgets(
    'programmatic scope changes release only the deselected entry focus',
    (tester) async {
      final inputFocus = FocusNode();
      addTearDown(inputFocus.dispose);
      final harness = await _pumpSidebar(tester, inputFocus: inputFocus);
      await _focusLabel(tester, '全部文章');
      harness.timeline.setTimelineScope(
        silent: true,
        silentGroupId: harness.group.id,
      );
      await tester.pumpAndSettle();
      expect(_focus(tester, '全部文章').hasFocus, false);
      expect(_focus(tester, 'Silent category').hasFocus, false);
      inputFocus.requestFocus();
      await tester.pumpAndSettle();
      harness.timeline.setTimelineScope();
      await tester.pumpAndSettle();
      expect(inputFocus.hasPrimaryFocus, true);
    },
  );

  testWidgets(
    'Tab keeps a visible focus target and Enter activates the unselected entry',
    (tester) async {
      final harness = await _pumpSidebar(tester);
      await _focusLabel(tester, '全部文章');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_focus(tester, '垃圾拦截').hasPrimaryFocus, true);
      expect(harness.page.value, 0);
      expect(_selected(tester, '垃圾拦截'), false);
      final ink = tester.widget<InkWell>(
        find
            .ancestor(of: find.text('垃圾拦截'), matching: find.byType(InkWell))
            .first,
      );
      expect(ink.canRequestFocus, true);
      expect(
        ink.focusColor ??
            Theme.of(tester.element(find.text('垃圾拦截'))).focusColor,
        isNot(Colors.transparent),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(harness.page.value, 1);
      expect(_selected(tester, '垃圾拦截'), true);
      expect(_focus(tester, '垃圾拦截').hasPrimaryFocus, true);
    },
  );

  testWidgets(
    'the disclosure button only changes expansion and removal disposes focus safely',
    (tester) async {
      final harness = await _pumpSidebar(tester);
      await _focusLabel(tester, '全部文章');
      final row = find
          .ancestor(
            of: find.text('Silent category'),
            matching: find.byType(Row),
          )
          .first;
      await tester.tap(
        find.descendant(of: row, matching: find.byType(IconButton)).first,
      );
      await tester.pumpAndSettle();
      expect(
        harness.subscriptions.isExpanded('silent-group:${harness.group.id}'),
        false,
      );
      expect(harness.timeline.isSilentSelected.value, false);
      expect(_selected(tester, '全部文章'), true);
      await tester.tap(find.text('Silent category'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
