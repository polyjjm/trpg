import 'package:flutter/material.dart';

import '../../core/user/user_profile.dart';
import '../../core/user/user_profile_repository.dart';
import '../data/admin_story_repository.dart';
import '../models/admin_story_pack.dart';
import '../models/story_pack_type.dart';
import '../widgets/admin_theme.dart';

/// "전체 작품 목록" — 모든 작가의 스토리팩을 가로질러 보여준다. 지금은
/// 필터 없는 단순 목록이다 — 작가/상태별로 좁혀 보는 기능은 팩 단위
/// "상태" 개념 자체가 아직 없어서(지금은 노드 단위로만 status가 있다)
/// 별도로 설계하기 전까지 미룬다.
class AllStoryPacksSection extends StatefulWidget {
  final AdminStoryRepository storyRepository;
  final UserProfileRepository userProfileRepository;

  const AllStoryPacksSection({
    super.key,
    required this.storyRepository,
    required this.userProfileRepository,
  });

  @override
  State<AllStoryPacksSection> createState() => _AllStoryPacksSectionState();
}

class _AllStoryPacksSectionState extends State<AllStoryPacksSection> {
  late final Stream<List<AdminStoryPack>> _packsStream = widget.storyRepository.watchPacks();
  late final Stream<List<UserProfile>> _authorsStream = widget.userProfileRepository.watchAuthors();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('전체 작품 목록', style: TextStyle(fontSize: 16, color: AdminColors.ivory, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              '모든 작가의 스토리팩이에요. 작가/상태별로 좁혀 보는 기능은 아직 없어요 — 따로 설계해서 추가할 예정이에요.',
              style: TextStyle(fontSize: 12, color: AdminColors.muted, height: 1.5),
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<UserProfile>>(
              stream: _authorsStream,
              builder: (context, authorsSnapshot) {
                final authorNameByUid = {
                  for (final author in authorsSnapshot.data ?? const <UserProfile>[]) author.uid: author.displayName,
                };

                return StreamBuilder<List<AdminStoryPack>>(
                  stream: _packsStream,
                  builder: (context, packsSnapshot) {
                    if (packsSnapshot.hasError) {
                      return SelectableText(
                        '작품 목록을 불러오지 못했어요: ${packsSnapshot.error}',
                        style: const TextStyle(fontSize: 12, color: AdminColors.danger),
                      );
                    }
                    if (packsSnapshot.connectionState == ConnectionState.waiting) {
                      return const Text('불러오는 중...', style: TextStyle(fontSize: 13, color: AdminColors.muted));
                    }

                    final packs = packsSnapshot.data ?? const <AdminStoryPack>[];
                    if (packs.isEmpty) {
                      return const Text('등록된 스토리팩이 없어요.', style: TextStyle(fontSize: 13, color: AdminColors.muted));
                    }

                    return Column(
                      children: [
                        for (final pack in packs)
                          _PackRow(
                            pack: pack,
                            authorName: authorNameByUid[pack.authorId] ?? pack.authorId,
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PackRow extends StatelessWidget {
  final AdminStoryPack pack;
  final String authorName;

  const _PackRow({required this.pack, required this.authorName});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AdminColors.panel,
        border: Border.all(color: AdminColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pack.title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AdminColors.ivory),
                ),
                const SizedBox(height: 4),
                Text(
                  '작가: ${authorName.isEmpty ? '(알 수 없음)' : authorName}'
                  '${pack.genres.isNotEmpty ? ' · ${pack.genres.join(', ')}' : ''}',
                  style: const TextStyle(fontSize: 11, color: AdminColors.muted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: AdminColors.panel2, borderRadius: BorderRadius.circular(999)),
            child: Text(
              pack.type == StoryPackType.interactive ? '인터랙티브' : '선형',
              style: const TextStyle(fontSize: 12, color: AdminColors.ivory),
            ),
          ),
        ],
      ),
    );
  }
}
