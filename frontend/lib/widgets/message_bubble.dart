import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/message.dart';
import '../core/theme/app_theme.dart';

class MessageBubble extends StatefulWidget {
  final Message message;
  final bool hideToolCalls;

  const MessageBubble({
    super.key,
    required this.message,
    this.hideToolCalls = false,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // 保持widget状态，避免重建

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用以支持 AutomaticKeepAliveClientMixin
    final isUser = widget.message.role == MessageRole.user;
    final isSystem = widget.message.role == MessageRole.system;
    final appColors = context.appColors;

    if (isSystem) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          decoration: BoxDecoration(
            color: appColors.toolBackground.withOpacity(0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            widget.message.content,
            style: TextStyle(
              color: appColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    // 如果启用了隐藏工具调用，检查消息是否只包含工具调用内容
    if (widget.hideToolCalls) {
      final hasNonToolContent = widget.message.contentBlocks.any((block) =>
        block.type != ContentBlockType.toolUse &&
        block.type != ContentBlockType.toolResult
      );

      // 如果消息只包含工具调用内容，完全隐藏这个消息气泡
      if (!hasNonToolContent) {
        return const SizedBox.shrink();
      }
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          left: isUser ? 48 : 16,
          right: isUser ? 16 : 48,
          top: 8,
          bottom: 8,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser ? appColors.userBubble : appColors.claudeBubble,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...widget.message.contentBlocks.map((block) => _buildContentBlock(context, block)),
            const SizedBox(height: 4),
            // 时间和复制按钮放在同一行
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatTime(widget.message.timestamp),
                  style: TextStyle(
                    color: appColors.textTertiary,
                    fontSize: 10,
                  ),
                ),
                // 复制按钮（仅assistant消息）
                if (!isUser)
                  InkWell(
                    onTap: () => _copyMessageContent(context),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.copy,
                        size: 14,
                        color: appColors.textTertiary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentBlock(BuildContext context, ContentBlock block) {
    switch (block.type) {
      case ContentBlockType.text:
        return _buildTextBlock(context, block.text ?? '');

      case ContentBlockType.thinking:
        return _buildThinkingBlock(context, block.thinking ?? '');

      case ContentBlockType.toolUse:
        // 如果设置了隐藏工具调用，返回空 widget
        if (widget.hideToolCalls) return const SizedBox.shrink();
        return _buildToolUseBlock(
          context,
          name: block.name ?? 'unknown',
          input: block.input ?? {},
        );

      case ContentBlockType.toolResult:
        // 如果设置了隐藏工具调用，返回空 widget
        if (widget.hideToolCalls) return const SizedBox.shrink();
        return _buildToolResultBlock(
          context,
          content: block.content,
          isError: block.isError ?? false,
        );

      case ContentBlockType.image:
        return _buildImageBlock(context, block);

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTextBlock(BuildContext context, String text) {
    if (text.isEmpty) return const SizedBox.shrink();

    final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
    final appColors = context.appColors;

    // 检查是否包含代码块
    final codeBlockPattern = RegExp(r'```(\w*)[\r\n]+([\s\S]*?)[\r\n]+```');
    final matches = codeBlockPattern.allMatches(text).toList();

    // 如果没有代码块，使用 Text 直接渲染（外层的 SelectionArea 会处理选择）
    if (matches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            color: textPrimary,
            fontSize: 15,
            height: 1.5,
          ),
        ),
      );
    }

    // 有代码块，手动处理
    return _buildTextWithCodeBlocks(context, text, matches, textPrimary, appColors);
  }

  Widget _buildTextWithCodeBlocks(BuildContext context, String text, List<RegExpMatch> matches, Color textPrimary, AppColorExtension appColors) {
    final widgets = <Widget>[];
    int lastIndex = 0;

    for (final match in matches) {
      // 添加代码块之前的文本
      if (match.start > lastIndex) {
        final beforeText = text.substring(lastIndex, match.start);
        if (beforeText.trim().isNotEmpty) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                beforeText,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ),
          );
        }
      }

      // 添加代码块
      final language = (match.group(1)?.isEmpty ?? true)
          ? _detectLanguage(match.group(2) ?? '')
          : match.group(1)!;
      final code = match.group(2) ?? '';
      widgets.add(_buildCodeBlock(context, code, language, appColors, textPrimary));

      lastIndex = match.end;
    }

    // 添加最后一个代码块之后的文本
    if (lastIndex < text.length) {
      final afterText = text.substring(lastIndex);
      if (afterText.trim().isNotEmpty) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              afterText,
              style: TextStyle(
                color: textPrimary,
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildCodeBlock(BuildContext context, String code, String language, AppColorExtension appColors, Color textPrimary) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = Theme.of(context).dividerColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: appColors.toolBackground.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部标题栏（语言标签和复制按钮）
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 语言标签
                Row(
                  children: [
                    Icon(
                      Icons.code,
                      size: 14,
                      color: appColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      language.toUpperCase(),
                      style: TextStyle(
                        color: appColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                // 复制按钮
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('代码已复制到剪贴板'),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.content_copy,
                          size: 12,
                          color: appColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '复制',
                          style: TextStyle(
                            color: appColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 代码内容（带语法高亮）
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: appColors.codeBackground,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text.rich(
              TextSpan(
                children: _buildHighlightedCode(code, language, isDark, textPrimary),
              ),
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _detectLanguage(String code) {
    if (code.contains('import ') && code.contains('def ')) return 'python';
    if (code.contains('function') || code.contains('const ') || code.contains('let ')) return 'javascript';
    if (code.contains('class ') && code.contains('public ')) return 'java';
    if (code.contains('#include') || code.contains('int main')) return 'cpp';
    if (code.contains('package ') && code.contains('func ')) return 'go';
    if (code.contains('fn ') && code.contains('let mut')) return 'rust';
    if (code.contains('<?php')) return 'php';
    if (code.contains('SELECT ') || code.contains('FROM ')) return 'sql';
    if (code.contains('<html') || code.contains('<div')) return 'html';
    if (code.contains('{') && code.contains('margin:')) return 'css';
    return 'dart';
  }

  // 构建高亮代码的 TextSpan 列表
  List<TextSpan> _buildHighlightedCode(String code, String language, bool isDark, Color textPrimary) {
    final theme = _getCodeTheme(isDark);
    final lines = code.split('\n');
    final spans = <TextSpan>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (language == 'python') {
        spans.add(_highlightPythonLine(line, theme, textPrimary));
      } else if (language == 'javascript' || language == 'dart') {
        spans.add(_highlightJavaScriptLine(line, theme, textPrimary));
      } else {
        spans.add(TextSpan(text: line, style: TextStyle(color: textPrimary)));
      }
      if (i < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }
    return spans;
  }

  TextSpan _highlightPythonLine(String line, Map<String, TextStyle> theme, Color textPrimary) {
    final keywords = ['def', 'class', 'import', 'from', 'if', 'else', 'elif', 'for', 'while', 'return', 'try', 'except', 'finally', 'with', 'as', 'in', 'is', 'and', 'or', 'not', 'True', 'False', 'None', 'print', 'range', 'len'];
    final keywordPattern = RegExp('\\b(${keywords.join('|')})\\b');
    final stringPattern = RegExp(r'''(['"])(?:(?!\1).)*\1''');
    final commentPattern = RegExp(r'#.*$');
    return _buildLineSpan(line, textPrimary, theme, keywordPattern, stringPattern, commentPattern);
  }

  TextSpan _highlightJavaScriptLine(String line, Map<String, TextStyle> theme, Color textPrimary) {
    final keywords = ['function', 'const', 'let', 'var', 'if', 'else', 'for', 'while', 'return', 'class', 'new', 'this', 'import', 'export', 'from', 'async', 'await', 'true', 'false', 'null'];
    final keywordPattern = RegExp('\\b(${keywords.join('|')})\\b');
    final stringPattern = RegExp(r'''(['"`])(?:(?!\1).)*\1''');
    final commentPattern = RegExp(r'//.*$');
    return _buildLineSpan(line, textPrimary, theme, keywordPattern, stringPattern, commentPattern);
  }

  TextSpan _buildLineSpan(String line, Color textPrimary, Map<String, TextStyle> theme, RegExp keywordPattern, RegExp stringPattern, RegExp commentPattern) {
    final children = <TextSpan>[];

    // 检查注释（优先级最高）
    final commentMatch = commentPattern.firstMatch(line);
    if (commentMatch != null) {
      if (commentMatch.start > 0) {
        final beforeComment = line.substring(0, commentMatch.start);
        children.addAll(_highlightSegment(beforeComment, textPrimary, theme, keywordPattern, stringPattern));
      }
      children.add(TextSpan(text: commentMatch.group(0), style: theme['comment']));
      return TextSpan(children: children);
    }

    // 处理字符串、关键字
    children.addAll(_highlightSegment(line, textPrimary, theme, keywordPattern, stringPattern));
    return TextSpan(children: children);
  }

  List<TextSpan> _highlightSegment(String text, Color textPrimary, Map<String, TextStyle> theme, RegExp keywordPattern, RegExp stringPattern) {
    final spans = <TextSpan>[];
    int currentIndex = 0;

    // 先处理字符串
    for (final match in stringPattern.allMatches(text)) {
      if (match.start > currentIndex) {
        final beforeString = text.substring(currentIndex, match.start);
        spans.addAll(_highlightKeywords(beforeString, textPrimary, theme, keywordPattern));
      }
      spans.add(TextSpan(text: match.group(0), style: theme['string']));
      currentIndex = match.end;
    }

    if (currentIndex < text.length) {
      final remaining = text.substring(currentIndex);
      spans.addAll(_highlightKeywords(remaining, textPrimary, theme, keywordPattern));
    }

    return spans;
  }

  List<TextSpan> _highlightKeywords(String text, Color textPrimary, Map<String, TextStyle> theme, RegExp keywordPattern) {
    final spans = <TextSpan>[];
    int currentIndex = 0;

    for (final match in keywordPattern.allMatches(text)) {
      if (match.start > currentIndex) {
        final beforeKeyword = text.substring(currentIndex, match.start);
        spans.add(TextSpan(text: beforeKeyword, style: TextStyle(color: textPrimary)));
      }
      spans.add(TextSpan(text: match.group(0), style: theme['keyword']));
      currentIndex = match.end;
    }

    if (currentIndex < text.length) {
      spans.add(TextSpan(text: text.substring(currentIndex), style: TextStyle(color: textPrimary)));
    }

    return spans;
  }

  Map<String, TextStyle> _getCodeTheme(bool isDark) {
    if (isDark) {
      return {
        'keyword': const TextStyle(color: Color(0xFFC586C0), fontWeight: FontWeight.w500),
        'string': const TextStyle(color: Color(0xFFCE9178)),
        'comment': const TextStyle(color: Color(0xFF6A9955), fontStyle: FontStyle.italic),
      };
    } else {
      return {
        'keyword': const TextStyle(color: Color(0xFF8B4789), fontWeight: FontWeight.w500),
        'string': const TextStyle(color: Color(0xFF0A7D2E)),
        'comment': const TextStyle(color: Color(0xFF008000), fontStyle: FontStyle.italic),
      };
    }
  }

  Widget _buildImageBlock(BuildContext context, ContentBlock block) {
    if (block.imageData == null || block.imageData!.isEmpty) {
      return const SizedBox.shrink();
    }

    final appColors = context.appColors;
    final dividerColor = Theme.of(context).dividerColor;

    // 使用图片数据的哈希作为 key，确保相同图片不会重新构建
    final imageKey = ValueKey(block.imageData!.hashCode);

    return Container(
      key: imageKey,
      margin: const EdgeInsets.only(bottom: 8),
      constraints: const BoxConstraints(
        maxWidth: 300,
        maxHeight: 300,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: dividerColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          base64Decode(block.imageData!),
          fit: BoxFit.contain,
          gaplessPlayback: true, // 防止图片闪烁
          cacheWidth: 600, // 缓存宽度，提高性能
          cacheHeight: 600, // 缓存高度，限制内存使用
          filterQuality: FilterQuality.medium, // 平衡质量和性能
          errorBuilder: (context, error, stackTrace) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image, color: appColors.textSecondary),
                  const SizedBox(height: 8),
                  Text(
                    '图片加载失败',
                    style: TextStyle(color: appColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildThinkingBlock(BuildContext context, String thinking) {
    if (thinking.isEmpty) return const SizedBox.shrink();

    final appColors = context.appColors;
    final dividerColor = Theme.of(context).dividerColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: appColors.toolBackground.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology, size: 16, color: appColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                '思考中',
                style: TextStyle(
                  color: appColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            thinking,
            style: TextStyle(
              color: appColors.textSecondary,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolUseBlock(BuildContext context, {required String name, required Map<String, dynamic> input}) {
    final appColors = context.appColors;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: appColors.toolBackground.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primaryColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.build, size: 16, color: primaryColor),
              const SizedBox(width: 4),
              Text(
                '工具调用: $name',
                style: TextStyle(
                  color: primaryColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (input.isNotEmpty) ...[
            const SizedBox(height: 4),
            Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: appColors.codeBackground,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    JsonEncoder.withIndent('  ').convert(input),
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: JsonEncoder.withIndent('  ').convert(input)));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('参数已复制到剪贴板'),
                          duration: Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: appColors.codeBackground.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        Icons.copy,
                        size: 14,
                        color: appColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolResultBlock(BuildContext context, {required dynamic content, required bool isError}) {
    // 提取文本内容
    String displayContent = '';
    if (content is String) {
      displayContent = content;
    } else if (content is List) {
      final buffer = StringBuffer();
      for (var item in content) {
        if (item is Map) {
          if (item['type'] == 'text') {
            buffer.writeln(item['text'] ?? '');
          } else if (item['type'] == 'image') {
            buffer.writeln('[图片]');
          }
        } else if (item is String) {
          buffer.writeln(item);
        }
      }
      displayContent = buffer.toString().trim();
    } else if (content != null) {
      displayContent = content.toString();
    }

    if (displayContent.isEmpty) return const SizedBox.shrink();

    final appColors = context.appColors;
    final errorColor = Theme.of(context).colorScheme.error;
    final dividerColor = Theme.of(context).dividerColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isError
            ? errorColor.withOpacity(0.1)
            : appColors.toolBackground.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isError
              ? errorColor.withOpacity(0.3)
              : dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isError ? Icons.error_outline : Icons.check_circle_outline,
                    size: 16,
                    color: isError ? errorColor : appColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isError ? '工具错误' : '工具结果',
                    style: TextStyle(
                      color: isError ? errorColor : appColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              // 添加复制按钮
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: displayContent));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('工具结果已复制到剪贴板'),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.copy,
                    size: 14,
                    color: appColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            displayContent,
            style: TextStyle(
              color: appColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // 复制整个消息内容
  void _copyMessageContent(BuildContext context) {
    final buffer = StringBuffer();

    for (var block in widget.message.contentBlocks) {
      if (block.type == ContentBlockType.text && block.text != null) {
        buffer.writeln(block.text);
      } else if (block.type == ContentBlockType.thinking && block.thinking != null) {
        buffer.writeln('[思考]: ${block.thinking}');
      } else if (block.type == ContentBlockType.toolUse) {
        if (block.name != null) {
          buffer.writeln('[工具调用]: ${block.name}');
        }
        if (block.input != null) {
          buffer.writeln('参数: ${JsonEncoder.withIndent('  ').convert(block.input)}');
        }
      } else if (block.type == ContentBlockType.toolResult) {
        if (block.toolUseId != null) {
          buffer.writeln('[工具结果]: ${block.toolUseId}');
        }
        if (block.content != null) {
          buffer.writeln(block.content.toString());
        }
      }
    }

    if (buffer.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: buffer.toString().trim()));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制到剪贴板'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }
}
