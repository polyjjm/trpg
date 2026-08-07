import '../../../core/constants/asset_paths.dart';
import 'story_choice.dart';

class StoryNode {
  final String id;
  final String dayLabel;
  final String title;
  final String text;
  final String backgroundImage;
  final List<StoryChoice> choices;

  const StoryNode({
    required this.id,
    required this.dayLabel,
    required this.title,
    required this.text,
    required this.choices,
    this.backgroundImage = BackgroundPaths.chapter1Bg,
  });

  bool get isEnding => choices.isEmpty;
}
