import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/services/ui_incident_trace.dart';

void main() {
  test('bounded prelude retains order and correlates active overlays', () {
    final trace = UiIncidentTrace(capacity: 3, activeLimit: 2);
    for (var i = 0; i < 5; i++) {
      trace.record({'event': 'action', 'index': i});
    }
    trace.opened(1, {'requestId': 7, 'component': 'Toast'});
    trace.opened(2, {'requestId': 8, 'component': 'Toast'});
    trace.opened(3, {'component': 'Tooltip'});
    trace.closed(2);
    final incident = trace.incident('build')!;
    expect((incident['recent'] as List).map((e) => e['index']), [2, 3, 4]);
    expect((incident['activeOverlays'] as List).single['id'], 3);
  });
  test('new error phases capture independently; storms do not overwrite first prelude', () {
    final trace = UiIncidentTrace();
    final start = DateTime.utc(2026, 10, 24);
    trace.record({'event': 'before'});
    final first = trace.incident('hitTest', at: start)!;
    trace.record({'event': 'after'});
    expect(
      trace.incident('hitTest', at: start.add(const Duration(seconds: 2))),
      isNull,
    );
    expect(
      trace.incident('build', at: start.add(const Duration(seconds: 2))),
      isNotNull,
    );
    expect((first['recent'] as List), hasLength(1));
    expect(
      trace.incident('hitTest', at: start.add(const Duration(minutes: 1))),
      isNotNull,
    );
  });
}
