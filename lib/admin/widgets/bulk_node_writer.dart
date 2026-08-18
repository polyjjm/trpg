import 'package:flutter/material.dart';

import '../../core/text/paragraph_blocks.dart';
import 'admin_theme.dart';
import 'labeled_field.dart';

/// splitIntoPages()가 만든 페이지 하나 — 아직 저장 전, 미리보기 단계의 텍스트다.
class BulkPagePreview {
  final String text;
  final int charCount;

  const BulkPagePreview({required this.text, required this.charCount});
}

/// 전체 본문을 문단 경계(빈 줄, splitIntoParagraphs와 같은 규칙)에서만 나눠,
/// [maxCharsPerPage]를 넘지 않는 페이지들로 묶는다 — 문단 중간이 잘리는 일은
/// 없다. 문단 하나가 그 자체로 한도를 넘으면(예: 아주 긴 한 문단) 그 문단만
/// 통째로 넘치는 페이지 하나가 된다 — 문단을 강제로 쪼개지는 않는다.
List<BulkPagePreview> splitIntoPages(String fullText, int maxCharsPerPage) {
  final paragraphs = splitIntoParagraphs(fullText);
  final pages = <BulkPagePreview>[];
  var buffer = <String>[];

  void flush() {
    if (buffer.isEmpty) return;
    final text = buffer.join('\n\n');
    pages.add(BulkPagePreview(text: text, charCount: text.length));
    buffer = [];
  }

  for (final paragraph in paragraphs) {
    final candidateLength = [...buffer, paragraph].join('\n\n').length;
    if (buffer.isNotEmpty && candidateLength > maxCharsPerPage) {
      flush();
    }
    buffer.add(paragraph);
  }
  flush();

  return pages;
}

/// 선형 스토리 전용 "한 번에 쓰기" 모드 — 큰 텍스트 하나를 붙여넣고 글자 수
/// 기준으로 미리 나눠본 뒤, 확인되면 페이지 수만큼 초안 노드를 한 번에 만든다.
/// 실제 Firestore 쓰기는 [onSave] 콜백(StoryTabView가 구현)에 맡긴다 — 이
/// 위젯은 입력/분할/미리보기 UI만 담당한다.
class BulkNodeWriter extends StatefulWidget {
  final Future<void> Function(List<BulkPagePreview> pages) onSave;

  const BulkNodeWriter({super.key, required this.onSave});

  @override
  State<BulkNodeWriter> createState() => _BulkNodeWriterState();
}

class _BulkNodeWriterState extends State<BulkNodeWriter> {
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _charLimitController = TextEditingController(
    text: '250',
  );

  List<BulkPagePreview>? _preview;
  bool _saving = false;

  @override
  void dispose() {
    _textController.dispose();
    _charLimitController.dispose();
    super.dispose();
  }

  void _handlePreview() {
    final limit = int.tryParse(_charLimitController.text.trim());
    setState(() {
      _preview = splitIntoPages(
        _textController.text,
        (limit == null || limit <= 0) ? 250 : limit,
      );
    });
  }

  Future<void> _handleSave() async {
    final preview = _preview;
    if (preview == null || preview.isEmpty) return;

    setState(() => _saving = true);
    await widget.onSave(preview);
    if (!mounted) return;

    setState(() {
      _saving = false;
      _preview = null;
      _textController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '전체 이야기를 한 번에 붙여넣고, 글자 수 기준으로 페이지(노드)를 나눠서 만들어요. '
              '문단(빈 줄로 구분)은 항상 페이지 경계에서만 나뉘고 중간에 잘리지 않아요.',
              style: TextStyle(
                fontSize: 12,
                color: AdminColors.muted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            LabeledField(
              label: '전체 본문 (문단 사이에 빈 줄을 하나 넣어 구분하세요)',
              child: TextFormField(
                controller: _textController,
                minLines: 16,
                maxLines: 32,
                style: TextStyle(
                  color: AdminColors.inputText,
                  fontSize: 13,
                  height: 1.6,
                ),
                decoration: adminInputDecoration(
                  hintText: '전체 이야기를 붙여넣거나 입력하세요.',
                ),
                onChanged: (_) {
                  if (_preview != null) setState(() => _preview = null);
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 160,
                  child: LabeledField(
                    label: '페이지당 글자 수',
                    child: TextFormField(
                      controller: _charLimitController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(
                        color: AdminColors.inputText,
                        fontSize: 13,
                      ),
                      decoration: adminInputDecoration(),
                      onChanged: (_) {
                        if (_preview != null) setState(() => _preview = null);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _textController.text.trim().isEmpty
                      ? null
                      : _handlePreview,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    '페이지 분할 미리보기',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (preview != null) ...[
              const SizedBox(height: 22),
              Text(
                preview.isEmpty
                    ? '나눌 내용이 없어요.'
                    : '${preview.length}개 페이지로 나뉘어요',
                style: TextStyle(
                  fontSize: 13,
                  color: AdminColors.ivory,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < preview.length; i++)
                _PagePreviewCard(index: i, page: preview[i]),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _saving ? null : _handleSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminColors.gold,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    _saving ? '저장 중...' : '${preview.length}개 노드로 저장하고 승인 요청',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _PagePreviewCard extends StatelessWidget {
  final int index;
  final BulkPagePreview page;

  const _PagePreviewCard({required this.index, required this.page});

  @override
  Widget build(BuildContext context) {
    final flattened = page.text.replaceAll('\n', ' ');
    final excerpt = flattened.length > 60
        ? '${flattened.substring(0, 60)}…'
        : flattened;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminColors.panel2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AdminColors.panel,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                fontSize: 12,
                color: AdminColors.gold,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              excerpt,
              style: TextStyle(fontSize: 12, color: AdminColors.ivory),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${page.charCount}자',
            style: TextStyle(fontSize: 11, color: AdminColors.muted),
          ),
        ],
      ),
    );
  }
}
