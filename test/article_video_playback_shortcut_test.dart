import 'package:fourier/pages/article/widgets/article_video_playback_shortcut.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('only the active article video handles playback toggles', (
    tester,
  ) async {
    final firstOwner = Object();
    final secondOwner = Object();
    var firstToggles = 0;
    var secondToggles = 0;

    ArticleVideoPlaybackShortcut.activate(firstOwner, () {
      firstToggles++;
    });
    expect(ArticleVideoPlaybackShortcut.requestToggle(firstOwner), isTrue);
    await tester.pump();
    expect(firstToggles, 1);

    ArticleVideoPlaybackShortcut.activate(secondOwner, () {
      secondToggles++;
    });
    expect(ArticleVideoPlaybackShortcut.requestToggle(firstOwner), isFalse);
    expect(ArticleVideoPlaybackShortcut.requestToggle(secondOwner), isTrue);
    await tester.pump();
    expect(secondToggles, 1);

    ArticleVideoPlaybackShortcut.deactivate(firstOwner);
    expect(ArticleVideoPlaybackShortcut.isActive(secondOwner), isTrue);
    ArticleVideoPlaybackShortcut.deactivate(secondOwner);
    expect(ArticleVideoPlaybackShortcut.requestToggle(secondOwner), isFalse);
  });
}
