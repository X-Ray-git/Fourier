import 'package:get/get.dart';

import '../timeline/timeline_controller.dart';

class MainController extends GetxController {
  final currentIndex = 0.obs;
  DateTime? _lastTimelineNavTapAt;
  _TimelineSourceReturn? _timelineSourceReturn;

  void changeIndex(int index) {
    final now = DateTime.now();
    if (index == currentIndex.value) {
      if (index == 0 &&
          _lastTimelineNavTapAt != null &&
          now.difference(_lastTimelineNavTapAt!).inMilliseconds < 300) {
        _lastTimelineNavTapAt = null;
        if (Get.isRegistered<TimelineController>()) {
          Get.find<TimelineController>().scrollToTop();
        }
        return;
      }
      if (index == 0) {
        _lastTimelineNavTapAt = now;
      }
      return;
    }
    if (currentIndex.value == 0) {
      _timelineSourceReturn = null;
    }
    currentIndex.value = index;
    _lastTimelineNavTapAt = index == 0 ? now : null;
  }

  /// Selects a page without treating repeated keyboard navigation as a
  /// sidebar double-click that scrolls the timeline to the top.
  void selectIndex(int index) {
    currentIndex.value = index;
    _lastTimelineNavTapAt = null;
  }

  void beginTimelineSourceNavigation({
    required String destinationFeedId,
    required int returnIndex,
  }) {
    _timelineSourceReturn = _TimelineSourceReturn(
      destinationFeedId: destinationFeedId,
      returnIndex: returnIndex,
    );
  }

  void validateTimelineSourceNavigation({
    required bool silent,
    required String? feedId,
    required String? category,
  }) {
    final pending = _timelineSourceReturn;
    if (pending == null) return;
    if (silent || category != null || feedId != pending.destinationFeedId) {
      _timelineSourceReturn = null;
    }
  }

  bool tryReturnFromTimelineSource({
    required bool silent,
    required String? feedId,
    required String? category,
  }) {
    validateTimelineSourceNavigation(
      silent: silent,
      feedId: feedId,
      category: category,
    );
    final pending = _timelineSourceReturn;
    if (pending == null || currentIndex.value != 0) return false;

    _timelineSourceReturn = null;
    selectIndex(pending.returnIndex);
    return true;
  }
}

class _TimelineSourceReturn {
  const _TimelineSourceReturn({
    required this.destinationFeedId,
    required this.returnIndex,
  });

  final String destinationFeedId;
  final int returnIndex;
}
