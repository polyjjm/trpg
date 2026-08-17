import 'package:flutter/material.dart';

import '../../core/user/user_profile.dart';
import '../../core/user/user_profile_repository.dart';
import '../data/admin_story_repository.dart';
import '../models/admin_story_pack.dart';
import '../widgets/admin_theme.dart';

/// "작가 관리" — 승인된 작가(role == 'author') 목록과 각자의 스토리팩 개수.
/// 읽기 전용이다 — 정지/자격 회수 같은 조치는 아직 없고, 자리만 마련해 둔다.
class AuthorManagementSection extends StatefulWidget {
  final UserProfileRepository userProfileRepository;
  final AdminStoryRepository storyRepository;

  const AuthorManagementSection({
    super.key,
    required this.userProfileRepository,
    required this.storyRepository,
  });

  @override
  State<AuthorManagementSection> createState() => _AuthorManagementSectionState();
}

class _AuthorManagementSectionState extends State<AuthorManagementSection> {
  late final Stream<List<UserProfile>> _authorsStream = widget.userProfileRepository.watchAuthors();
  late final Stream<List<AdminStoryPack>> _packsStream = widget.storyRepository.watchPacks();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('작가 관리', style: TextStyle(fontSize: 16, color: AdminColors.ivory, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              '승인된 작가 계정과 각자 만든 스토리팩 수예요. 정지·자격 회수 같은 조치는 아직 없어요.',
              style: TextStyle(fontSize: 12, color: AdminColors.muted, height: 1.5),
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<UserProfile>>(
              stream: _authorsStream,
              builder: (context, authorsSnapshot) {
                if (authorsSnapshot.hasError) {
                  return SelectableText(
                    '작가 목록을 불러오지 못했어요: ${authorsSnapshot.error}',
                    style: const TextStyle(fontSize: 12, color: AdminColors.danger),
                  );
                }
                if (authorsSnapshot.connectionState == ConnectionState.waiting) {
                  return const Text('불러오는 중...', style: TextStyle(fontSize: 13, color: AdminColors.muted));
                }

                final authors = List<UserProfile>.of(authorsSnapshot.data ?? const <UserProfile>[])
                  ..sort((a, b) => a.displayName.compareTo(b.displayName));
                if (authors.isEmpty) {
                  return const Text('승인된 작가가 아직 없어요.', style: TextStyle(fontSize: 13, color: AdminColors.muted));
                }

                return StreamBuilder<List<AdminStoryPack>>(
                  stream: _packsStream,
                  builder: (context, packsSnapshot) {
                    final packs = packsSnapshot.data ?? const <AdminStoryPack>[];
                    final packCountByAuthor = <String, int>{};
                    for (final pack in packs) {
                      packCountByAuthor[pack.authorId] = (packCountByAuthor[pack.authorId] ?? 0) + 1;
                    }

                    return Column(
                      children: [
                        for (final author in authors)
                          _AuthorRow(profile: author, packCount: packCountByAuthor[author.uid] ?? 0),
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

class _AuthorRow extends StatelessWidget {
  final UserProfile profile;
  final int packCount;

  const _AuthorRow({required this.profile, required this.packCount});

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
                  profile.displayName.isEmpty ? '(이름 없음)' : profile.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AdminColors.ivory),
                ),
                const SizedBox(height: 2),
                Text(profile.email, style: const TextStyle(fontSize: 11, color: AdminColors.muted)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: AdminColors.panel2, borderRadius: BorderRadius.circular(999)),
            child: Text('작품 $packCount개', style: const TextStyle(fontSize: 12, color: AdminColors.ivory)),
          ),
        ],
      ),
    );
  }
}
