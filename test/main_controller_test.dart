import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/pages/main/main_controller.dart';

void main() {
  test('timeline source navigation returns to its originating page', () {
    final controller = MainController()..selectIndex(1);

    controller.beginTimelineSourceNavigation(
      destinationFeedId: 'feed-1',
      returnIndex: 1,
    );
    controller.selectIndex(0);

    expect(
      controller.tryReturnFromTimelineSource(
        silent: false,
        feedId: 'feed-1',
        category: null,
      ),
      isTrue,
    );
    expect(controller.currentIndex.value, 1);
  });

  test('changing the destination scope invalidates source return', () {
    final controller = MainController()..selectIndex(1);

    controller.beginTimelineSourceNavigation(
      destinationFeedId: 'feed-1',
      returnIndex: 1,
    );
    controller.selectIndex(0);

    expect(
      controller.tryReturnFromTimelineSource(
        silent: false,
        feedId: 'feed-2',
        category: null,
      ),
      isFalse,
    );
    expect(controller.currentIndex.value, 0);
  });

  test('manual navigation away from timeline clears source return', () {
    final controller = MainController()..selectIndex(1);

    controller.beginTimelineSourceNavigation(
      destinationFeedId: 'feed-1',
      returnIndex: 1,
    );
    controller.selectIndex(0);
    controller.changeIndex(2);
    controller.selectIndex(0);

    expect(
      controller.tryReturnFromTimelineSource(
        silent: false,
        feedId: 'feed-1',
        category: null,
      ),
      isFalse,
    );
  });
}
