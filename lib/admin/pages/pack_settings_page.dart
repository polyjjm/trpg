import 'package:flutter/material.dart';

import '../data/admin_bgm_repository.dart';
import '../data/admin_image_repository.dart';
import '../data/admin_story_repository.dart';
import '../data/admin_tts_voice_repository.dart';
import '../data/genre_repository.dart';
import '../models/admin_bgm.dart';
import '../models/admin_image.dart';
import '../models/admin_image_category.dart';
import '../models/admin_story_node_summary.dart';
import '../models/admin_story_pack.dart';
import '../models/admin_tts_voice.dart';
import '../models/genre.dart';
import '../models/node_status.dart';
import '../models/pack_serialization_status.dart';
import '../widgets/admin_theme.dart';
import '../widgets/bgm_picker_field.dart';
import '../widgets/image_picker_field.dart';
import '../widgets/info_banner.dart';
import '../widgets/labeled_field.dart';
import '../widgets/tts_voice_picker_field.dart';

/// 스토리팩의 메타데이터(제목/장르/설명/표지)를 편집하는 화면.
///
/// 제목/설명 등 편집 가능한 필드는 NodeEditor와 같은 이유로 서버 스냅샷에
/// 직접 바인딩하지 않는다(TextEditingController/로컬 Set에 한 번만 시드해서
/// 들고 있고, 타이핑 중에 들어온 변경이 폼을 덮어쓰지 않게 한다) — 하지만
/// serializationStatus/pendingMetadataAction 같은 승인 상태 필드는 폼이 아니라
/// 배너 표시 전용이라 [_packStream]으로 실시간 반영한다(다른 화면에서 admin이
/// 승인/반려해도 새로고침 없이 배너가 바로 바뀐다).
///
/// 두 단계 흐름:
/// - 연재 시작 전(draft/rejected): "임시저장" / "연재 시작 승인 요청" — 단,
///   발행된(published) 노드가 최소 1개 있어야 요청할 수 있다. 제목/장르/설명뿐인
///   빈 팩을 admin이 검토하게 하지 않으려는 의도적인 순서다 — 노드 작성/승인
///   자체는 이 팩의 연재 시작 승인 여부와 무관하게 언제든 가능하다.
/// - 연재 승인 후(approved): "임시저장" / "변경사항 승인 요청" — admin이
///   승인해야 반영되고, 그 전까지 독자에게는 liveMetadata(마지막 승인
///   버전)가 그대로 보인다.
class PackSettingsPage extends StatefulWidget {
  final String packId;
  final AdminStoryRepository repository;
  final AdminImageRepository imageRepository;
  final AdminBgmRepository bgmRepository;
  final AdminTtsVoiceRepository ttsVoiceRepository;

  const PackSettingsPage({
    super.key,
    required this.packId,
    required this.repository,
    required this.imageRepository,
    required this.bgmRepository,
    required this.ttsVoiceRepository,
  });

  @override
  State<PackSettingsPage> createState() => _PackSettingsPageState();
}

class _PackSettingsPageState extends State<PackSettingsPage> {
  final GenreRepository _genreRepository = GenreRepository();

  late final Stream<AdminStoryPack?> _packStream = widget.repository.watchPack(
    widget.packId,
  );
  late final Stream<List<Genre>> _genresStream = _genreRepository
      .watchActiveGenres();
  late final Stream<List<AdminImage>> _imagesStream = widget.imageRepository
      .watchImages();
  late final Stream<List<AdminBgm>> _bgmsStream = widget.bgmRepository
      .watchBgmLibrary();
  late final Stream<List<AdminTtsVoice>> _ttsVoicesStream = widget
      .ttsVoiceRepository
      .watchVoices();
  late final Stream<List<AdminStoryNodeSummary>> _nodeSummariesStream = widget
      .repository
      .watchNodeSummaries(widget.packId);

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _salePriceController = TextEditingController();
  final Set<String> _selectedGenreSlugs = {};
  String? _coverImageId;
  String? _defaultBackgroundImageId;
  String? _defaultBgmId;
  String? _defaultTtsVoiceId;
  DateTime? _discountStartAt;
  DateTime? _discountEndAt;

  bool _initialized = false;
  bool _dirty = false;
  bool _saving = false;
  bool _refreshingTtsVoices = false;

  Future<void> _handleRefreshTtsVoices() async {
    if (_refreshingTtsVoices) return;
    setState(() => _refreshingTtsVoices = true);
    try {
      await widget.ttsVoiceRepository.refreshVoices();
    } catch (e) {
      // 예전엔 catch가 없어서 refreshTypecastVoices가 실패해도(예: 인증/
      // 권한/Typecast API 오류) 로딩 스피너만 원상복구되고 사용자에게는 아무
      // 신호도 없이 조용히 "보이스 목록이 비어 있어요" 상태로 남았다 — 실제로
      // 겪은 버그(디버깅 시 클라이언트가 호출을 시도했는지조차 알 수 없었다).
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('보이스 목록 새로고침에 실패했어요: $e')));
    } finally {
      if (mounted) setState(() => _refreshingTtsVoices = false);
    }
  }

  void _initFrom(AdminStoryPack pack) {
    if (_initialized) return;
    _initialized = true;
    _titleController.text = pack.title;
    _descriptionController.text = pack.description;
    _priceController.text = '${pack.price}';
    _salePriceController.text = pack.salePrice != null
        ? '${pack.salePrice}'
        : '';
    _selectedGenreSlugs.addAll(pack.genres);
    _coverImageId = pack.coverImageId;
    _defaultBackgroundImageId = pack.defaultBackgroundImage;
    _defaultBgmId = pack.defaultBgmId;
    _defaultTtsVoiceId = pack.defaultTtsVoiceId;
    _discountStartAt = pack.discountStartAt;
    _discountEndAt = pack.discountEndAt;
    _titleController.addListener(_markDirty);
    _descriptionController.addListener(_markDirty);
    _priceController.addListener(_markDirty);
    _salePriceController.addListener(_markDirty);
  }

  int get _priceValue => int.tryParse(_priceController.text.trim()) ?? 0;

  int? get _salePriceValue {
    final text = _salePriceController.text.trim();
    return text.isEmpty ? null : int.tryParse(text);
  }

  Future<void> _pickDiscountDate({required bool isStart}) async {
    final initial =
        (isStart ? _discountStartAt : _discountEndAt) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _discountStartAt = picked;
      } else {
        _discountEndAt = picked;
      }
      _dirty = true;
    });
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _toggleGenre(String slug) {
    setState(() {
      if (!_selectedGenreSlugs.remove(slug)) {
        _selectedGenreSlugs.add(slug);
      }
      _dirty = true;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _salePriceController.dispose();
    super.dispose();
  }

  Future<void> _handleSaveDraft() async {
    setState(() => _saving = true);
    try {
      await widget.repository.saveDraftPackSettings(
        widget.packId,
        title: _titleController.text.trim(),
        genres: _selectedGenreSlugs.toList(),
        description: _descriptionController.text.trim(),
        coverImageId: _coverImageId,
        price: _priceValue,
        salePrice: _salePriceValue,
        discountStartAt: _discountStartAt,
        discountEndAt: _discountEndAt,
        defaultBackgroundImage: _defaultBackgroundImageId,
        defaultBgmId: _defaultBgmId,
        defaultTtsVoiceId: _defaultTtsVoiceId,
      );
    } catch (e) {
      _handleError(e);
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('임시저장했어요.')));
  }

  Future<void> _handleRequestSerialization() async {
    setState(() => _saving = true);
    try {
      // 승인 요청 전에 지금 폼 내용부터 저장해서, admin이 검토하는 값이 화면에
      // 보이는 값과 항상 같도록 한다.
      await widget.repository.saveDraftPackSettings(
        widget.packId,
        title: _titleController.text.trim(),
        genres: _selectedGenreSlugs.toList(),
        description: _descriptionController.text.trim(),
        coverImageId: _coverImageId,
        price: _priceValue,
        salePrice: _salePriceValue,
        discountStartAt: _discountStartAt,
        discountEndAt: _discountEndAt,
        defaultBackgroundImage: _defaultBackgroundImageId,
        defaultBgmId: _defaultBgmId,
        defaultTtsVoiceId: _defaultTtsVoiceId,
      );
      await widget.repository.requestSerialization(widget.packId);
    } catch (e) {
      _handleError(e);
      return;
    }
    _finishSaving();
  }

  Future<void> _handleRequestMetadataEdit() async {
    setState(() => _saving = true);
    try {
      await widget.repository.requestMetadataEdit(
        widget.packId,
        title: _titleController.text.trim(),
        genres: _selectedGenreSlugs.toList(),
        description: _descriptionController.text.trim(),
        coverImageId: _coverImageId,
        price: _priceValue,
        salePrice: _salePriceValue,
        discountStartAt: _discountStartAt,
        discountEndAt: _discountEndAt,
        defaultBgmId: _defaultBgmId,
        defaultTtsVoiceId: _defaultTtsVoiceId,
      );
    } catch (e) {
      _handleError(e);
      return;
    }
    _finishSaving();
  }

  /// Firestore 쓰기가 실패했을 때(권한 거부 등) 화면이 아무 반응 없이 멈춘 것처럼
  /// 보이는 대신 스낵바로 드러낸다 — 예전엔 이 예외들이 잡히지 않고 조용히
  /// 사라져서, 실패했는데도 성공한 것처럼 보이는 버그가 있었다.
  void _handleError(Object error) {
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('저장에 실패했어요: $error')));
  }

  /// 승인 요청/임시저장 액션이 성공한 뒤 로딩 상태만 정리한다 — 배너에 쓰는
  /// serializationStatus/pendingMetadataAction 등은 더 이상 수동으로 다시
  /// 읽어올 필요가 없다. [_packStream]이 이미 라이브라 admin의 승인/반려는
  /// 물론 이 액션 자체가 만든 변경도 스트림을 통해 자동으로 반영된다.
  void _finishSaving() {
    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.bg,
      appBar: AppBar(
        backgroundColor: AdminColors.panel,
        title: Text(
          '팩 설정',
          style: TextStyle(color: AdminColors.ivory, fontSize: 16),
        ),
        iconTheme: IconThemeData(color: AdminColors.ivory),
      ),
      body: StreamBuilder<AdminStoryPack?>(
        stream: _packStream,
        builder: (context, snapshot) {
          final pack = snapshot.data;
          if (pack == null) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AdminColors.gold),
              );
            }
            return Center(
              child: Text(
                '스토리팩을 찾을 수 없어요.',
                style: TextStyle(color: AdminColors.muted),
              ),
            );
          }
          // 제목/장르/설명/표지는 폼(TextEditingController/로컬 Set)이 한 번만
          // 시드해서 들고 있는다 — 그 뒤로는 스트림이 갱신돼도 다시 덮어쓰지
          // 않는다(클래스 상단 doc 참고).
          _initFrom(pack);

          return StreamBuilder<List<AdminStoryNodeSummary>>(
            stream: _nodeSummariesStream,
            builder: (context, nodeSnapshot) {
              final hasPublishedNode =
                  (nodeSnapshot.data ?? const <AdminStoryNodeSummary>[]).any(
                    (node) => node.status == NodeStatus.published,
                  );
              return _buildForm(pack, hasPublishedNode);
            },
          );
        },
      ),
    );
  }

  Widget _buildForm(AdminStoryPack pack, bool hasPublishedNode) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._buildBanners(pack, hasPublishedNode),
            LabeledField(
              label: '제목',
              child: TextFormField(
                controller: _titleController,
                style: TextStyle(color: AdminColors.inputText, fontSize: 13),
                decoration: adminInputDecoration(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '장르',
              style: TextStyle(fontSize: 12, color: AdminColors.muted),
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<Genre>>(
              stream: _genresStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return SelectableText(
                    '장르 목록을 불러오지 못했어요: ${snapshot.error}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminColors.danger,
                    ),
                  );
                }
                final genres = snapshot.data ?? const <Genre>[];
                if (genres.isEmpty) {
                  return Text(
                    '등록된 장르가 없어요.',
                    style: TextStyle(fontSize: 12, color: AdminColors.muted),
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final genre in genres)
                      _GenreChip(
                        label: genre.name,
                        selected: _selectedGenreSlugs.contains(genre.slug),
                        onTap: () => _toggleGenre(genre.slug),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            LabeledField(
              label: '설명',
              child: TextFormField(
                controller: _descriptionController,
                minLines: 4,
                maxLines: 8,
                style: TextStyle(
                  color: AdminColors.inputText,
                  fontSize: 13,
                  height: 1.5,
                ),
                decoration: adminInputDecoration(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: LabeledField(
                    label: '가격 (코인)',
                    child: TextFormField(
                      controller: _priceController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(
                        color: AdminColors.inputText,
                        fontSize: 13,
                      ),
                      decoration: adminInputDecoration(hintText: '0 = 무료'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LabeledField(
                    label: '할인가 (코인, 선택)',
                    child: TextFormField(
                      controller: _salePriceController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(
                        color: AdminColors.inputText,
                        fontSize: 13,
                      ),
                      decoration: adminInputDecoration(hintText: '(할인 없음)'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: LabeledField(
                    label: '할인 시작일 (선택, 비워두면 즉시 적용)',
                    child: _DateField(
                      date: _discountStartAt,
                      onTap: () => _pickDiscountDate(isStart: true),
                      onClear: () => setState(() {
                        _discountStartAt = null;
                        _dirty = true;
                      }),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LabeledField(
                    label: '할인 종료일 (선택, 비워두면 계속 적용)',
                    child: _DateField(
                      date: _discountEndAt,
                      onTap: () => _pickDiscountDate(isStart: false),
                      onClear: () => setState(() {
                        _discountEndAt = null;
                        _dirty = true;
                      }),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LabeledField(
              label: '표지 이미지',
              child: StreamBuilder<List<AdminImage>>(
                stream: _imagesStream,
                builder: (context, snapshot) {
                  final images = snapshot.data ?? const <AdminImage>[];
                  return ImagePickerField(
                    currentId: _coverImageId,
                    images: images,
                    onChanged: (id) => setState(() {
                      _coverImageId = id;
                      _dirty = true;
                    }),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            LabeledField(
              label: '기본 배경 이미지 (노드가 배경을 따로 안 고르면 이 값이 쓰여요)',
              child: StreamBuilder<List<AdminImage>>(
                stream: _imagesStream,
                builder: (context, snapshot) {
                  final images = snapshot.data ?? const <AdminImage>[];
                  return ImagePickerField(
                    currentId: _defaultBackgroundImageId,
                    images: images,
                    filterCategory: AdminImageCategory.background,
                    onChanged: (id) => setState(() {
                      _defaultBackgroundImageId = id;
                      _dirty = true;
                    }),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            LabeledField(
              label: '기본 배경음악 (노드가 배경음악을 따로 안 고르면 리딩 세션 시작 시 이 값이 재생돼요)',
              child: StreamBuilder<List<AdminBgm>>(
                stream: _bgmsStream,
                builder: (context, snapshot) {
                  final bgms = snapshot.data ?? const <AdminBgm>[];
                  return BgmPickerField(
                    currentId: _defaultBgmId,
                    bgmLibrary: bgms,
                    onChanged: (id) => setState(() {
                      _defaultBgmId = id;
                      _dirty = true;
                    }),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            LabeledField(
              label: '기본 내레이터 보이스 (노드가 보이스를 따로 안 고르면 이 값이 쓰여요, Typecast)',
              child: StreamBuilder<List<AdminTtsVoice>>(
                stream: _ttsVoicesStream,
                builder: (context, snapshot) {
                  final voices = snapshot.data ?? const <AdminTtsVoice>[];
                  return TtsVoicePickerField(
                    currentId: _defaultTtsVoiceId,
                    voices: voices,
                    onChanged: (id) => setState(() {
                      _defaultTtsVoiceId = id;
                      _dirty = true;
                    }),
                    onRefresh: _handleRefreshTtsVoices,
                    refreshing: _refreshingTtsVoices,
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            _buildSaveBar(pack, hasPublishedNode),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBanners(AdminStoryPack pack, bool hasPublishedNode) {
    final banners = <Widget>[];

    if (_dirty) {
      banners.add(
        const InfoBanner(
          style: InfoBannerStyle.dirty,
          text: '저장하지 않은 변경사항이 있어요. "임시저장"을 눌러야 다음에 다시 열었을 때 남아있어요.',
        ),
      );
    }

    if (pack.canRequestSerialization && !hasPublishedNode) {
      banners.add(
        const InfoBanner(
          style: InfoBannerStyle.dirty,
          text:
              '아직 발행된 노드가 없어요. 먼저 "스토리 노드" 탭에서 노드를 하나 이상 작성하고 승인받아야 '
              '연재 시작을 요청할 수 있어요 — admin이 실제 콘텐츠를 보고 판단할 수 있어야 하기 때문이에요.',
        ),
      );
    }

    if (pack.serializationStatus == PackSerializationStatus.draft) {
      if (hasPublishedNode) {
        banners.add(
          const InfoBanner(
            style: InfoBannerStyle.dirty,
            text: '아직 연재를 시작하지 않았어요. "연재 시작 승인 요청"을 보내야 독자 라이브러리에 노출될 수 있어요.',
          ),
        );
      }
    } else if (pack.serializationStatus == PackSerializationStatus.pending) {
      banners.add(
        const InfoBanner(
          style: InfoBannerStyle.dirty,
          text: '연재 시작 승인을 기다리는 중이에요. 승인 전까지는 독자에게 보이지 않아요.',
        ),
      );
    } else if (pack.serializationStatus == PackSerializationStatus.rejected) {
      final reason = pack.serializationRejectionReason;
      banners.add(
        InfoBanner(
          style: InfoBannerStyle.dirty,
          text:
              '연재 시작 요청이 반려됐어요.${reason != null && reason.isNotEmpty ? ' 사유: $reason' : ''}'
              '${hasPublishedNode ? ' 내용을 고친 뒤 다시 요청할 수 있어요.' : ''}',
        ),
      );
    } else if (pack.serializationStatus == PackSerializationStatus.approved) {
      if (pack.pendingMetadataAction == 'edit') {
        banners.add(
          const InfoBanner(
            style: InfoBannerStyle.dirty,
            text: '메타데이터 변경 승인을 기다리는 중이에요. 승인 전까지 독자에게는 이전 정보가 그대로 보여요.',
          ),
        );
      } else {
        banners.add(
          const InfoBanner(
            style: InfoBannerStyle.live,
            text:
                '이 팩은 연재 중이에요. 여기서 수정해도 바로 반영되지 않고, "변경사항 승인 요청"을 보내서 '
                '관리자가 승인해야 독자에게 반영돼요.',
          ),
        );
        final reason = pack.metadataRejectionReason;
        if (reason != null && reason.isNotEmpty) {
          banners.add(
            InfoBanner(
              style: InfoBannerStyle.dirty,
              text: '최근 메타데이터 변경 요청이 반려됐어요. 사유: $reason',
            ),
          );
        }
      }
    }

    return banners;
  }

  Widget _buildSaveBar(AdminStoryPack pack, bool hasPublishedNode) {
    final canRequestSerialization =
        pack.canRequestSerialization && hasPublishedNode;
    final blockedBySerializationContent =
        pack.canRequestSerialization && !hasPublishedNode;

    return Container(
      padding: const EdgeInsets.only(top: 18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AdminColors.border)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton(
            onPressed: _saving ? null : _handleSaveDraft,
            style: OutlinedButton.styleFrom(
              foregroundColor: AdminColors.muted,
              side: BorderSide(color: AdminColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('임시저장', style: TextStyle(fontSize: 13)),
          ),
          if (canRequestSerialization)
            ElevatedButton(
              onPressed: _saving ? null : _handleRequestSerialization,
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.gold,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 11,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                '연재 시작 승인 요청',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            )
          else if (pack.canRequestMetadataEdit)
            ElevatedButton(
              onPressed: _saving ? null : _handleRequestMetadataEdit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.gold,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 11,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                '변경사항 승인 요청',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            )
          else if (blockedBySerializationContent)
            Text(
              '발행된 노드가 있어야 연재 시작을 요청할 수 있어요.',
              style: TextStyle(fontSize: 12, color: AdminColors.muted),
            )
          else
            Text(
              '승인 대기 중이라 지금은 새 요청을 보낼 수 없어요.',
              style: TextStyle(fontSize: 12, color: AdminColors.muted),
            ),
        ],
      ),
    );
  }
}

class _GenreChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GenreChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AdminColors.statusPendingBg : AdminColors.panel2,
          border: Border.all(
            color: selected
                ? AdminColors.statusPendingText
                : AdminColors.border,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? AdminColors.statusPendingText : AdminColors.muted,
          ),
        ),
      ),
    );
  }
}

/// home_banner_management_section.dart/point_package_management_section.dart의
/// _DateField와 같은 모양 — 이 화면만의 사본이다(관리자 위젯을 각 파일이
/// 따로 들고 있는 이 코드베이스의 기존 관례를 그대로 따른다).
class _DateField extends StatelessWidget {
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _DateField({
    required this.date,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final date = this.date;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: AdminColors.inputFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AdminColors.inputBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                date == null
                    ? '(선택 안 함)'
                    : '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontSize: 13,
                  color: date == null
                      ? AdminColors.muted
                      : AdminColors.inputText,
                ),
              ),
            ),
            if (date != null)
              InkWell(
                onTap: onClear,
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AdminColors.muted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
