extension DurationVideoFormat on Duration {
  /// 将 Duration 格式化为视频播放器常见的时间字符串
  /// 
  /// 大于等于 1 小时： H:MM:SS
  /// 小于 1 小时： M:SS
  String toVideoFormatString() {
    final hours = inHours;
    final mins = inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = inSeconds.remainder(60).toString().padLeft(2, '0');
    
    if (hours > 0) {
      return '$hours:$mins:$secs';
    } else {
      final m = inMinutes.remainder(60).toString();
      return '$m:$secs';
    }
  }
}
