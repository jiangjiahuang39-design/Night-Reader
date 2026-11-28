/// 點擊、音量鍵與選單翻頁時捲過一屏要多久。
enum ReaderPageTurnSpeed {
  fast('快', Duration(milliseconds: 160)),
  normal('標準', Duration(milliseconds: 260)),
  slow('慢', Duration(milliseconds: 400));

  const ReaderPageTurnSpeed(this.label, this.duration);

  final String label;
  final Duration duration;

  /// 沒設定過或認不得時：慢（維護者自己讀書用的設定，2026-11-06）。
  static const ReaderPageTurnSpeed defaultSpeed = slow;

  static ReaderPageTurnSpeed parse(String? name) => values.firstWhere(
    (speed) => speed.name == name,
    orElse: () => defaultSpeed,
  );
}


/// 橫向翻頁的動效（僅包含適合橫向跟手的樣式）。
enum ReaderHorizontalPageTurnStyle {
  slide('平移'),
  cover('覆蓋'),
  forward('推進'),
  glide('滑入');

  const ReaderHorizontalPageTurnStyle(this.label);

  final String label;

  static const ReaderHorizontalPageTurnStyle defaultStyle = slide;

  static ReaderHorizontalPageTurnStyle parse(String? name) => values.firstWhere(
    (style) => style.name == name,
    orElse: () => defaultStyle,
  );
}