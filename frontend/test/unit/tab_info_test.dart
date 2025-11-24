import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cc_mobile/screens/tab_manager_screen.dart';

/// TabInfo 类的单元测试
void main() {
  group('TabInfo 基础测试', () {
    test('创建 Home 类型 TabInfo', () {
      final tab = TabInfo(
        id: 'home_123',
        type: TabType.home,
        title: '主页',
        content: const SizedBox(),
      );

      expect(tab.id, 'home_123');
      expect(tab.type, TabType.home);
      expect(tab.title, '主页');
      expect(tab.hasNewReply, false);
      expect(tab.cwd, isNull);
      expect(tab.isCodex, false);
    });

    test('创建 Chat 类型 TabInfo', () {
      final tab = TabInfo(
        id: 'chat_456',
        type: TabType.chat,
        title: '项目对话',
        content: const SizedBox(),
        cwd: '/path/to/project',
        isCodex: true,
      );

      expect(tab.id, 'chat_456');
      expect(tab.type, TabType.chat);
      expect(tab.title, '项目对话');
      expect(tab.cwd, '/path/to/project');
      expect(tab.isCodex, true);
    });

    test('创建带历史记录的 TabInfo', () {
      final previousContent = const Text('Previous');
      final tab = TabInfo(
        id: 'tab_789',
        type: TabType.home,
        title: '当前页',
        content: const SizedBox(),
        previousContent: previousContent,
        previousTitle: '上一页',
      );

      expect(tab.previousContent, previousContent);
      expect(tab.previousTitle, '上一页');
      expect(tab.previousPreviousContent, isNull);
      expect(tab.previousPreviousTitle, isNull);
    });

    test('创建带深层历史记录的 TabInfo', () {
      final prevPrevContent = const Text('PrevPrev');
      final prevContent = const Text('Prev');

      final tab = TabInfo(
        id: 'tab_deep',
        type: TabType.home,
        title: '当前页',
        content: const SizedBox(),
        previousContent: prevContent,
        previousTitle: '上一页',
        previousPreviousContent: prevPrevContent,
        previousPreviousTitle: '更上一页',
      );

      expect(tab.previousContent, prevContent);
      expect(tab.previousTitle, '上一页');
      expect(tab.previousPreviousContent, prevPrevContent);
      expect(tab.previousPreviousTitle, '更上一页');
    });
  });

  group('TabInfo hasNewReply 测试', () {
    test('默认无新回复', () {
      final tab = TabInfo(
        id: 'tab_1',
        type: TabType.chat,
        title: 'Test',
        content: const SizedBox(),
      );

      expect(tab.hasNewReply, false);
      expect(tab.hasNewReplyNotifier.value, false);
    });

    test('初始化时设置有新回复', () {
      final tab = TabInfo(
        id: 'tab_2',
        type: TabType.chat,
        title: 'Test',
        content: const SizedBox(),
        hasNewReply: true,
      );

      expect(tab.hasNewReply, true);
      expect(tab.hasNewReplyNotifier.value, true);
    });

    test('修改 hasNewReply 状态', () {
      final tab = TabInfo(
        id: 'tab_3',
        type: TabType.chat,
        title: 'Test',
        content: const SizedBox(),
      );

      // 修改状态
      tab.hasNewReply = true;
      tab.hasNewReplyNotifier.value = true;

      expect(tab.hasNewReply, true);
      expect(tab.hasNewReplyNotifier.value, true);

      // 清除状态
      tab.hasNewReply = false;
      tab.hasNewReplyNotifier.value = false;

      expect(tab.hasNewReply, false);
      expect(tab.hasNewReplyNotifier.value, false);
    });

    test('ValueNotifier 监听变化', () {
      final tab = TabInfo(
        id: 'tab_4',
        type: TabType.chat,
        title: 'Test',
        content: const SizedBox(),
      );

      int notifyCount = 0;
      tab.hasNewReplyNotifier.addListener(() {
        notifyCount++;
      });

      tab.hasNewReplyNotifier.value = true;
      expect(notifyCount, 1);

      tab.hasNewReplyNotifier.value = false;
      expect(notifyCount, 2);

      // 相同值不应触发通知
      tab.hasNewReplyNotifier.value = false;
      expect(notifyCount, 2);
    });
  });

  group('TabInfo dispose 测试', () {
    test('dispose 后 ValueNotifier 被释放', () {
      final tab = TabInfo(
        id: 'tab_dispose',
        type: TabType.chat,
        title: 'Test',
        content: const SizedBox(),
      );

      // 添加监听器
      bool listenerCalled = false;
      tab.hasNewReplyNotifier.addListener(() {
        listenerCalled = true;
      });

      // dispose
      tab.dispose();

      // dispose 后尝试修改值应该抛出异常
      expect(
        () => tab.hasNewReplyNotifier.value = true,
        throwsA(isA<FlutterError>()),
      );
    });
  });

  group('TabType 枚举测试', () {
    test('TabType 包含正确的值', () {
      expect(TabType.values.length, 2);
      expect(TabType.values.contains(TabType.home), true);
      expect(TabType.values.contains(TabType.chat), true);
    });

    test('TabType.home 和 TabType.chat 不相等', () {
      expect(TabType.home == TabType.chat, false);
    });
  });

  group('TabInfo ID 唯一性测试', () {
    test('不同 TabInfo 可以有相同 ID（逻辑上应避免）', () {
      final tab1 = TabInfo(
        id: 'same_id',
        type: TabType.home,
        title: 'Tab 1',
        content: const SizedBox(),
      );

      final tab2 = TabInfo(
        id: 'same_id',
        type: TabType.chat,
        title: 'Tab 2',
        content: const SizedBox(),
      );

      // 虽然 ID 相同，但它们是不同的对象
      expect(tab1.id, tab2.id);
      expect(identical(tab1, tab2), false);
    });

    test('使用时间戳生成唯一 ID', () {
      final timestamp1 = DateTime.now().millisecondsSinceEpoch;
      final id1 = 'home_$timestamp1';

      // 稍微延迟
      final timestamp2 = DateTime.now().millisecondsSinceEpoch + 1;
      final id2 = 'home_$timestamp2';

      expect(id1 == id2, false);
    });
  });

  group('TabInfo cwd 和 isCodex 测试', () {
    test('Chat 标签带 cwd', () {
      final tab = TabInfo(
        id: 'chat_cwd',
        type: TabType.chat,
        title: 'Project',
        content: const SizedBox(),
        cwd: 'C:\\Projects\\MyApp',
      );

      expect(tab.cwd, 'C:\\Projects\\MyApp');
      expect(tab.cwd!.isNotEmpty, true);
    });

    test('Chat 标签无 cwd', () {
      final tab = TabInfo(
        id: 'chat_no_cwd',
        type: TabType.chat,
        title: 'Project',
        content: const SizedBox(),
      );

      expect(tab.cwd, isNull);
    });

    test('isCodex 默认为 false', () {
      final tab = TabInfo(
        id: 'chat_default',
        type: TabType.chat,
        title: 'Project',
        content: const SizedBox(),
      );

      expect(tab.isCodex, false);
    });

    test('isCodex 设置为 true', () {
      final tab = TabInfo(
        id: 'chat_codex',
        type: TabType.chat,
        title: 'Codex Project',
        content: const SizedBox(),
        isCodex: true,
      );

      expect(tab.isCodex, true);
    });

    test('Home 类型标签的 cwd 和 isCodex', () {
      final tab = TabInfo(
        id: 'home_with_cwd',
        type: TabType.home,
        title: '主页',
        content: const SizedBox(),
        cwd: '/some/path', // Home 类型通常不需要 cwd
        isCodex: true,     // Home 类型通常不需要 isCodex
      );

      // 即使设置了，也应该能正常工作
      expect(tab.cwd, '/some/path');
      expect(tab.isCodex, true);
    });
  });

  group('TabInfo title 边界测试', () {
    test('空标题', () {
      final tab = TabInfo(
        id: 'empty_title',
        type: TabType.home,
        title: '',
        content: const SizedBox(),
      );

      expect(tab.title, '');
      expect(tab.title.isEmpty, true);
    });

    test('超长标题', () {
      final longTitle = 'A' * 100;
      final tab = TabInfo(
        id: 'long_title',
        type: TabType.home,
        title: longTitle,
        content: const SizedBox(),
      );

      expect(tab.title.length, 100);

      // 测试截断逻辑（UI 层面截断为 12 字符）
      final displayTitle = tab.title.length > 12
          ? '${tab.title.substring(0, 12)}...'
          : tab.title;
      expect(displayTitle, 'AAAAAAAAAAAA...');
    });

    test('包含特殊字符的标题', () {
      final tab = TabInfo(
        id: 'special_title',
        type: TabType.chat,
        title: '项目<测试>&"引号"',
        content: const SizedBox(),
      );

      expect(tab.title, '项目<测试>&"引号"');
    });

    test('包含 emoji 的标题', () {
      final tab = TabInfo(
        id: 'emoji_title',
        type: TabType.chat,
        title: '🚀 项目名称 📁',
        content: const SizedBox(),
      );

      expect(tab.title.contains('🚀'), true);
      expect(tab.title.contains('📁'), true);
    });
  });
}
