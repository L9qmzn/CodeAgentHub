import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cc_mobile/screens/tab_manager_screen.dart';

/// TabManager 业务逻辑测试
/// 这些测试不依赖 Widget，只测试纯逻辑
void main() {
  group('标签列表操作测试', () {
    late List<TabInfo> tabs;

    setUp(() {
      tabs = [];
    });

    tearDown(() {
      for (var tab in tabs) {
        tab.dispose();
      }
      tabs.clear();
    });

    test('添加标签到空列表', () {
      final tab = TabInfo(
        id: 'tab_1',
        type: TabType.home,
        title: '主页',
        content: const SizedBox(),
      );
      tabs.add(tab);

      expect(tabs.length, 1);
      expect(tabs.first.id, 'tab_1');
    });

    test('添加多个标签', () {
      for (int i = 0; i < 5; i++) {
        tabs.add(TabInfo(
          id: 'tab_$i',
          type: i == 0 ? TabType.home : TabType.chat,
          title: '标签 $i',
          content: const SizedBox(),
        ));
      }

      expect(tabs.length, 5);
      expect(tabs[0].type, TabType.home);
      expect(tabs[1].type, TabType.chat);
    });

    test('根据索引移除标签', () {
      for (int i = 0; i < 3; i++) {
        tabs.add(TabInfo(
          id: 'tab_$i',
          type: TabType.chat,
          title: '标签 $i',
          content: const SizedBox(),
        ));
      }

      final removedTab = tabs.removeAt(1);
      removedTab.dispose();

      expect(tabs.length, 2);
      expect(tabs[0].id, 'tab_0');
      expect(tabs[1].id, 'tab_2');
    });

    test('根据 ID 查找标签索引', () {
      for (int i = 0; i < 3; i++) {
        tabs.add(TabInfo(
          id: 'tab_$i',
          type: TabType.chat,
          title: '标签 $i',
          content: const SizedBox(),
        ));
      }

      final index = tabs.indexWhere((tab) => tab.id == 'tab_1');
      expect(index, 1);

      final notFoundIndex = tabs.indexWhere((tab) => tab.id == 'tab_999');
      expect(notFoundIndex, -1);
    });

    test('根据 ID 查找 chat 标签', () {
      tabs.add(TabInfo(
        id: 'home_1',
        type: TabType.home,
        title: '主页',
        content: const SizedBox(),
      ));
      tabs.add(TabInfo(
        id: 'chat_session_123',
        type: TabType.chat,
        title: '对话',
        content: const SizedBox(),
      ));

      final chatIndex = tabs.indexWhere(
        (tab) => tab.id == 'chat_session_123',
      );
      expect(chatIndex, 1);
    });

    test('替换指定索引的标签', () {
      tabs.add(TabInfo(
        id: 'old_tab',
        type: TabType.home,
        title: '旧标签',
        content: const SizedBox(),
      ));

      final oldTab = tabs[0];
      tabs[0] = TabInfo(
        id: 'new_tab',
        type: TabType.chat,
        title: '新标签',
        content: const SizedBox(),
      );
      oldTab.dispose();

      expect(tabs[0].id, 'new_tab');
      expect(tabs[0].type, TabType.chat);
    });

    test('清空标签列表', () {
      for (int i = 0; i < 3; i++) {
        tabs.add(TabInfo(
          id: 'tab_$i',
          type: TabType.chat,
          title: '标签 $i',
          content: const SizedBox(),
        ));
      }

      for (var tab in tabs) {
        tab.dispose();
      }
      tabs.clear();

      expect(tabs.isEmpty, true);
    });
  });

  group('标签索引边界测试', () {
    late List<TabInfo> tabs;
    late int currentIndex;

    setUp(() {
      tabs = [];
      currentIndex = 0;
    });

    tearDown(() {
      for (var tab in tabs) {
        tab.dispose();
      }
    });

    test('空列表时索引检查', () {
      expect(tabs.isEmpty, true);
      expect(currentIndex >= tabs.length || tabs.isEmpty, true);
    });

    test('移除最后一个标签后索引调整', () {
      for (int i = 0; i < 3; i++) {
        tabs.add(TabInfo(
          id: 'tab_$i',
          type: TabType.chat,
          title: '标签 $i',
          content: const SizedBox(),
        ));
      }
      currentIndex = 2; // 指向最后一个

      // 移除最后一个
      final removed = tabs.removeAt(2);
      removed.dispose();

      // 调整索引
      if (currentIndex >= tabs.length) {
        currentIndex = tabs.length - 1;
      }

      expect(currentIndex, 1);
    });

    test('移除中间标签后索引不变', () {
      for (int i = 0; i < 3; i++) {
        tabs.add(TabInfo(
          id: 'tab_$i',
          type: TabType.chat,
          title: '标签 $i',
          content: const SizedBox(),
        ));
      }
      currentIndex = 0;

      // 移除中间的
      final removed = tabs.removeAt(1);
      removed.dispose();

      // 索引小于移除位置，不需要调整
      expect(currentIndex, 0);
      expect(tabs.length, 2);
    });

    test('移除当前标签后索引调整', () {
      for (int i = 0; i < 3; i++) {
        tabs.add(TabInfo(
          id: 'tab_$i',
          type: TabType.chat,
          title: '标签 $i',
          content: const SizedBox(),
        ));
      }
      currentIndex = 1;

      // 移除当前标签
      final removed = tabs.removeAt(currentIndex);
      removed.dispose();

      // 调整索引到相同位置或前一个
      final newIndex = currentIndex >= tabs.length ? tabs.length - 1 : currentIndex;

      expect(newIndex, 1);
      expect(tabs[newIndex].id, 'tab_2');
    });
  });

  group('分屏模式逻辑测试', () {
    late List<TabInfo> leftTabs;
    late List<TabInfo> rightTabs;
    late bool isSplitScreen;
    late int rightCurrentIndex;

    setUp(() {
      leftTabs = [];
      rightTabs = [];
      isSplitScreen = false;
      rightCurrentIndex = 0;
    });

    tearDown(() {
      for (var tab in leftTabs) {
        tab.dispose();
      }
      for (var tab in rightTabs) {
        tab.dispose();
      }
    });

    test('开启分屏模式', () {
      // 模拟开启分屏
      isSplitScreen = true;

      // 添加右侧主页标签
      rightTabs.add(TabInfo(
        id: 'right_home_1',
        type: TabType.home,
        title: '主页',
        content: const SizedBox(),
      ));

      expect(isSplitScreen, true);
      expect(rightTabs.length, 1);
      expect(rightTabs.first.type, TabType.home);
    });

    test('关闭分屏模式清理右侧标签', () {
      isSplitScreen = true;

      // 添加多个右侧标签
      for (int i = 0; i < 3; i++) {
        rightTabs.add(TabInfo(
          id: 'right_tab_$i',
          type: i == 0 ? TabType.home : TabType.chat,
          title: '右侧标签 $i',
          content: const SizedBox(),
        ));
      }

      expect(rightTabs.length, 3);

      // 关闭分屏
      isSplitScreen = false;
      for (var tab in rightTabs) {
        tab.dispose();
      }
      rightTabs.clear();
      rightCurrentIndex = 0;

      expect(isSplitScreen, false);
      expect(rightTabs.isEmpty, true);
      expect(rightCurrentIndex, 0);
    });

    test('左右面板标签独立', () {
      isSplitScreen = true;

      // 左侧添加标签
      leftTabs.add(TabInfo(
        id: 'left_home',
        type: TabType.home,
        title: '左侧主页',
        content: const SizedBox(),
      ));

      // 右侧添加标签
      rightTabs.add(TabInfo(
        id: 'right_home',
        type: TabType.home,
        title: '右侧主页',
        content: const SizedBox(),
      ));

      // 左侧添加更多标签
      leftTabs.add(TabInfo(
        id: 'left_chat_1',
        type: TabType.chat,
        title: '左侧对话',
        content: const SizedBox(),
      ));

      expect(leftTabs.length, 2);
      expect(rightTabs.length, 1);
    });

    test('右侧面板边界检查 - 空列表', () {
      isSplitScreen = true;
      // 不添加任何标签

      // 边界检查
      final isEmpty = rightTabs.isEmpty || rightCurrentIndex >= rightTabs.length;
      expect(isEmpty, true);
    });

    test('右侧面板边界检查 - 索引越界', () {
      isSplitScreen = true;
      rightTabs.add(TabInfo(
        id: 'right_tab',
        type: TabType.home,
        title: '右侧标签',
        content: const SizedBox(),
      ));
      rightCurrentIndex = 5; // 故意设置越界

      final isOutOfBounds = rightCurrentIndex >= rightTabs.length;
      expect(isOutOfBounds, true);
    });
  });

  group('同目录新建对话逻辑测试', () {
    test('从 cwd 提取项目名称', () {
      const cwd = '/Users/test/Projects/MyApp';
      final projectName = cwd.split('/').last;

      expect(projectName, 'MyApp');
    });

    test('Windows 路径提取项目名称', () {
      const cwd = 'C:\\Users\\test\\Projects\\MyApp';
      final projectName = cwd.split('\\').last;

      expect(projectName, 'MyApp');
    });

    test('生成唯一的新会话 ID', () {
      final ids = <String>{};

      for (int i = 0; i < 100; i++) {
        final id = 'new_${DateTime.now().millisecondsSinceEpoch}_$i';
        ids.add(id);
      }

      // 所有 ID 都应该是唯一的
      expect(ids.length, 100);
    });

    test('新对话标签 ID 格式', () {
      const sessionId = 'new_1234567890';
      final tabId = 'chat_$sessionId';

      expect(tabId, 'chat_new_1234567890');
      expect(tabId.startsWith('chat_'), true);
    });

    test('右侧面板新对话标签 ID 格式', () {
      const sessionId = 'new_1234567890';
      final tabId = 'right_chat_$sessionId';

      expect(tabId, 'right_chat_new_1234567890');
      expect(tabId.startsWith('right_'), true);
    });
  });

  group('标签历史导航测试', () {
    test('保存上一个界面', () {
      final previousContent = const Text('Previous');

      final tab = TabInfo(
        id: 'current',
        type: TabType.chat,
        title: '当前',
        content: const SizedBox(),
        previousContent: previousContent,
        previousTitle: '上一个',
      );

      expect(tab.previousContent, isNotNull);
      expect(tab.previousTitle, '上一个');
    });

    test('恢复到上一个界面', () {
      final previousContent = const Text('Previous');

      final currentTab = TabInfo(
        id: 'current',
        type: TabType.chat,
        title: '当前',
        content: const SizedBox(),
        previousContent: previousContent,
        previousTitle: '上一个',
      );

      // 模拟恢复
      if (currentTab.previousContent != null) {
        final restoredTab = TabInfo(
          id: 'restored',
          type: TabType.home,
          title: currentTab.previousTitle ?? '主页',
          content: currentTab.previousContent!,
        );

        expect(restoredTab.title, '上一个');
        expect(restoredTab.type, TabType.home);

        restoredTab.dispose();
      }

      currentTab.dispose();
    });

    test('深层历史恢复到最底层', () {
      final prevPrevContent = const Text('PrevPrev');

      final tab = TabInfo(
        id: 'deep',
        type: TabType.chat,
        title: '深层',
        content: const SizedBox(),
        previousContent: const Text('Prev'),
        previousTitle: '上一层',
        previousPreviousContent: prevPrevContent,
        previousPreviousTitle: '最底层',
      );

      // 恢复时应该直接回到最底层
      Widget? targetContent = tab.previousContent;
      String? targetTitle = tab.previousTitle;

      if (tab.previousPreviousContent != null) {
        targetContent = tab.previousPreviousContent;
        targetTitle = tab.previousPreviousTitle;
      }

      expect(targetTitle, '最底层');

      tab.dispose();
    });
  });

  group('消息完成通知逻辑测试', () {
    late List<TabInfo> tabs;
    late int currentIndex;

    setUp(() {
      tabs = [];
      currentIndex = 0;

      for (int i = 0; i < 3; i++) {
        tabs.add(TabInfo(
          id: 'tab_$i',
          type: TabType.chat,
          title: '标签 $i',
          content: const SizedBox(),
        ));
      }
    });

    tearDown(() {
      for (var tab in tabs) {
        tab.dispose();
      }
    });

    test('当前标签完成不设置新回复标记', () {
      currentIndex = 1;
      final tabIndex = 1; // 当前标签

      // 当前标签完成，不应设置 hasNewReply
      if (tabIndex == currentIndex) {
        // 只显示完成提示，不设置标记
        expect(tabs[tabIndex].hasNewReply, false);
      }
    });

    test('后台标签完成设置新回复标记', () {
      currentIndex = 0;
      final tabIndex = 2; // 后台标签

      if (tabIndex != currentIndex && tabIndex < tabs.length) {
        tabs[tabIndex].hasNewReply = true;
        tabs[tabIndex].hasNewReplyNotifier.value = true;
      }

      expect(tabs[tabIndex].hasNewReply, true);
      expect(tabs[tabIndex].hasNewReplyNotifier.value, true);
    });

    test('切换到标签时清除新回复标记', () {
      // 先设置标记
      tabs[1].hasNewReply = true;
      tabs[1].hasNewReplyNotifier.value = true;

      // 切换到该标签
      currentIndex = 1;
      tabs[currentIndex].hasNewReply = false;
      tabs[currentIndex].hasNewReplyNotifier.value = false;

      expect(tabs[1].hasNewReply, false);
      expect(tabs[1].hasNewReplyNotifier.value, false);
    });
  });

  group('查找已存在标签测试', () {
    late List<TabInfo> tabs;

    setUp(() {
      tabs = [
        TabInfo(
          id: 'home_1',
          type: TabType.home,
          title: '主页',
          content: const SizedBox(),
        ),
        TabInfo(
          id: 'chat_session_abc',
          type: TabType.chat,
          title: '对话 ABC',
          content: const SizedBox(),
        ),
        TabInfo(
          id: 'chat_session_xyz',
          type: TabType.chat,
          title: '对话 XYZ',
          content: const SizedBox(),
        ),
      ];
    });

    tearDown(() {
      for (var tab in tabs) {
        tab.dispose();
      }
    });

    test('查找已存在的会话标签', () {
      const sessionId = 'session_abc';
      final tabId = 'chat_$sessionId';

      final existingIndex = tabs.indexWhere((tab) => tab.id == tabId);

      expect(existingIndex, 1);
    });

    test('查找不存在的会话标签', () {
      const sessionId = 'session_not_exist';
      final tabId = 'chat_$sessionId';

      final existingIndex = tabs.indexWhere((tab) => tab.id == tabId);

      expect(existingIndex, -1);
    });

    test('右侧面板查找已存在的会话标签', () {
      final rightTabs = [
        TabInfo(
          id: 'right_home_1',
          type: TabType.home,
          title: '主页',
          content: const SizedBox(),
        ),
        TabInfo(
          id: 'right_chat_session_abc',
          type: TabType.chat,
          title: '对话 ABC',
          content: const SizedBox(),
        ),
      ];

      const sessionId = 'session_abc';
      final tabId = 'right_chat_$sessionId';

      final existingIndex = rightTabs.indexWhere((tab) => tab.id == tabId);

      expect(existingIndex, 1);

      for (var tab in rightTabs) {
        tab.dispose();
      }
    });
  });
}
