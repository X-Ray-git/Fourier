import 'package:get/get.dart';
import '../timeline/timeline_controller.dart';

class MainController extends GetxController {
  final currentIndex = 0.obs;
  final isMacSidebarCollapsed = false.obs;
  DateTime? _lastTimelineNavTapAt;

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
    currentIndex.value = index;
    _lastTimelineNavTapAt = index == 0 ? now : null;
  }

  void toggleMacSidebar() {
    isMacSidebarCollapsed.value = !isMacSidebarCollapsed.value;
  }
}
