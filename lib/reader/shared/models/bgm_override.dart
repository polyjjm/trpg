/// StoryNode.bgmOverride(embedded map) — 이 노드에서만 storyPack의 기본
/// ambientBgm 대신 재생할 트랙 지정.
class BgmOverride {
  final String trackId;
  final int fadeInMs;
  final bool loop;

  const BgmOverride({
    required this.trackId,
    required this.fadeInMs,
    required this.loop,
  });

  factory BgmOverride.fromJson(Map<String, dynamic> json) {
    return BgmOverride(
      trackId: json['trackId'] as String? ?? '',
      fadeInMs: (json['fadeInMs'] as num?)?.toInt() ?? 0,
      loop: json['loop'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'trackId': trackId,
        'fadeInMs': fadeInMs,
        'loop': loop,
      };
}
