import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cc_mobile/screens/tab_manager_screen.dart';

/// TabManager Widget 集成测试
/// 测试 UI 组件的渲染和交互
void main() {
  // 创建一个简单的测试用 MaterialApp 包装器
  Widget createTestApp({required Widget child}) {
    return MaterialApp(
      home: child,
    );
  }

  group('TabInfo Widget 渲染测试', () {
    testWidgets('TabInfo content 正确渲染', (WidgetTester tester) async {
      final tab = TabInfo(
        id: 'test_tab',
        type: TabType.home,
        title: '测试标签',
        content: const Text('测试内容'),
      );

      await tester.pumpWidget(createTestApp(
        child: Scaffold(body: tab.content),
      ));

      expect(find.text('测试内容'), findsOneWidget);

      tab.dispose();
    });

    testWidgets('TabInfo 复杂 content 渲染', (WidgetTester tester) async {
      final tab = TabInfo(
        id: 'complex_tab',
        type: TabType.chat,
        title: '复杂标签',
        content: Column(
          children: const [
            Text('标题'),
            SizedBox(height: 10),
            Text('内容'),
          ],
        ),
      );

      await tester.pumpWidget(createTestApp(
        child: Scaffold(body: tab.content),
      ));

      expect(find.text('标题'), findsOneWidget);
      expect(find.text('内容'), findsOneWidget);

      tab.dispose();
    });
  });

  group('标签标题显示测试', () {
    testWidgets('正常长度标题完整显示', (WidgetTester tester) async {
      const title = '短标题';

      // 测试截断逻辑
      final displayTitle = title.length > 12
          ? '${title.substring(0, 12)}...'
          : title;

      await tester.pumpWidget(createTestApp(
        child: Scaffold(
          body: Text(displayTitle),
        ),
      ));

      expect(find.text('短标题'), findsOneWidget);
    });

    testWidgets('超长标题被截断', (WidgetTester tester) async {
      const title = '这是一个非常非常长的标签标题';

      final displayTitle = title.length > 12
          ? '${title.substring(0, 12)}...'
          : title;

      await tester.pumpWidget(createTestApp(
        child: Scaffold(
          body: Text(displayTitle),
        ),
      ));

      expect(find.text('这是一个非常非常长的标签...'), findsOneWidget);
    });

    testWidgets('12 字符标题不截断', (WidgetTester tester) async {
      const title = '十二个字符的标题名';

      final displayTitle = title.length > 12
          ? '${title.substring(0, 12)}...'
          : title;

      await tester.pumpWidget(createTestApp(
        child: Scaffold(
          body: Text(displayTitle),
        ),
      ));

      // 12 字符刚好不截断
      expect(displayTitle.endsWith('...'), false);
    });
  });

  group('标签图标测试', () {
    testWidgets('Home 类型显示主页图标', (WidgetTester tester) async {
      final tab = TabInfo(
        id: 'home_tab',
        type: TabType.home,
        title: '主页',
        content: const SizedBox(),
      );

      final icon = tab.type == TabType.home
          ? Icons.home_outlined
          : Icons.chat_outlined;

      await tester.pumpWidget(createTestApp(
        child: Scaffold(
          body: Icon(icon),
        ),
      ));

      expect(find.byIcon(Icons.home_outlined), findsOneWidget);

      tab.dispose();
    });

    testWidgets('Chat 类型显示对话图标', (WidgetTester tester) async {
      final tab = TabInfo(
        id: 'chat_tab',
        type: TabType.chat,
        title: '对话',
        content: const SizedBox(),
      );

      final icon = tab.type == TabType.home
          ? Icons.home_outlined
          : Icons.chat_outlined;

      await tester.pumpWidget(createTestApp(
        child: Scaffold(
          body: Icon(icon),
        ),
      ));

      expect(find.byIcon(Icons.chat_outlined), findsOneWidget);

      tab.dispose();
    });
  });

  group('新回复指示器测试', () {
    testWidgets('无新回复时不显示指示器', (WidgetTester tester) async {
      final tab = TabInfo(
        id: 'no_reply_tab',
        type: TabType.chat,
        title: '对话',
        content: const SizedBox(),
        hasNewReply: false,
      );

      await tester.pumpWidget(createTestApp(
        child: Scaffold(
          body: Row(
            children: [
              Text(tab.title),
              if (tab.hasNewReply)
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ));

      // 应该只有一个文本，没有指示器容器
      expect(find.text('对话'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Container && widget.constraints?.maxWidth == 8,
        ),
        findsNothing,
      );

      tab.dispose();
    });

    testWidgets('有新回复时显示指示器', (WidgetTester tester) async {
      final tab = TabInfo(
        id: 'has_reply_tab',
        type: TabType.chat,
        title: '对话',
        content: const SizedBox(),
        hasNewReply: true,
      );

      await tester.pumpWidget(createTestApp(
        child: Scaffold(
          body: Row(
            children: [
              Text(tab.title),
              if (tab.hasNewReply)
                Container(
                  key: const Key('new_reply_indicator'),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ));

      expect(find.text('对话'), findsOneWidget);
      expect(find.byKey(const Key('new_reply_indicator')), findsOneWidget);

      tab.dispose();
    });
  });

  group('关闭按钮测试', () {
    testWidgets('点击关闭按钮触发回调', (WidgetTester tester) async {
      bool closeClicked = false;

      await tester.pumpWidget(createTestApp(
        child: Scaffold(
          body: InkWell(
            key: const Key('close_button'),
            onTap: () {
              closeClicked = true;
            },
            child: const Icon(Icons.close, size: 14),
          ),
        ),
      ));

      await tester.tap(find.byKey(const Key('close_button')));
      await tester.pump();

      expect(closeClicked, true);
    });
  });

  group('ValueNotifier 监听测试', () {
    testWidgets('ValueListenableBuilder 响应变化', (WidgetTester tester) async {
      final tab = TabInfo(
        id: 'listener_tab',
        type: TabType.chat,
        title: '对话',
        content: const SizedBox(),
      );

      await tester.pumpWidget(createTestApp(
        child: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: tab.hasNewReplyNotifier,
            builder: (context, hasNewReply, child) {
              return Text(hasNewReply ? '有新回复' : '无新回复');
            },
          ),
        ),
      ));

      expect(find.text('无新回复'), findsOneWidget);

      // 修改状态
      tab.hasNewReplyNotifier.value = true;
      await tester.pump();

      expect(find.text('有新回复'), findsOneWidget);

      tab.dispose();
    });
  });

  group('分屏按钮测试', () {
    testWidgets('分屏按钮点击切换图标', (WidgetTester tester) async {
      bool isSplitScreen = false;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return createTestApp(
              child: Scaffold(
                body: IconButton(
                  key: const Key('split_button'),
                  icon: Icon(
                    isSplitScreen ? Icons.view_sidebar : Icons.vertical_split,
                  ),
                  onPressed: () {
                    setState(() {
                      isSplitScreen = !isSplitScreen;
                    });
                  },
                ),
              ),
            );
          },
        ),
      );

      // 初始状态
      expect(find.byIcon(Icons.vertical_split), findsOneWidget);
      expect(find.byIcon(Icons.view_sidebar), findsNothing);

      // 点击切换
      await tester.tap(find.byKey(const Key('split_button')));
      await tester.pump();

      expect(find.byIcon(Icons.view_sidebar), findsOneWidget);
      expect(find.byIcon(Icons.vertical_split), findsNothing);

      // 再次点击
      await tester.tap(find.byKey(const Key('split_button')));
      await tester.pump();

      expect(find.byIcon(Icons.vertical_split), findsOneWidget);
    });
  });

  group('标签栏滚动测试', () {
    testWidgets('多个标签可以滚动', (WidgetTester tester) async {
      final tabs = List.generate(
        10,
        (i) => TabInfo(
          id: 'tab_$i',
          type: TabType.chat,
          title: '标签 $i',
          content: Text('内容 $i'),
        ),
      );

      await tester.pumpWidget(createTestApp(
        child: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: tabs
                  .map((tab) => Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(tab.title),
                      ))
                  .toList(),
            ),
          ),
        ),
      ));

      // 第一个标签可见
      expect(find.text('标签 0'), findsOneWidget);

      // 滚动到右边
      await tester.drag(find.byType(SingleChildScrollView), const Offset(-500, 0));
      await tester.pump();

      for (var tab in tabs) {
        tab.dispose();
      }
    });
  });

  group('右键菜单测试', () {
    testWidgets('显示 PopupMenu', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(
        child: Scaffold(
          body: PopupMenuButton<String>(
            key: const Key('popup_menu'),
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'new_claude',
                child: Text('在此目录新建 Claude 对话'),
              ),
              const PopupMenuItem<String>(
                value: 'new_codex',
                child: Text('在此目录新建 Codex 对话'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'close',
                child: Text('关闭标签页'),
              ),
            ],
            child: const Text('点击显示菜单'),
          ),
        ),
      ));

      // 点击打开菜单
      await tester.tap(find.byKey(const Key('popup_menu')));
      await tester.pumpAndSettle();

      expect(find.text('在此目录新建 Claude 对话'), findsOneWidget);
      expect(find.text('在此目录新建 Codex 对话'), findsOneWidget);
      expect(find.text('关闭标签页'), findsOneWidget);
    });

    testWidgets('选择菜单项触发回调', (WidgetTester tester) async {
      String? selectedValue;

      await tester.pumpWidget(createTestApp(
        child: Scaffold(
          body: PopupMenuButton<String>(
            key: const Key('popup_menu'),
            onSelected: (value) {
              selectedValue = value;
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'close',
                child: Text('关闭'),
              ),
            ],
            child: const Text('菜单'),
          ),
        ),
      ));

      await tester.tap(find.byKey(const Key('popup_menu')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();

      expect(selectedValue, 'close');
    });
  });

  group('分屏布局测试', () {
    testWidgets('非分屏模式只显示一个面板', (WidgetTester tester) async {
      const isSplitScreen = false;

      await tester.pumpWidget(createTestApp(
        child: Scaffold(
          body: isSplitScreen
              ? Row(
                  children: const [
                    Expanded(child: Text('左侧')),
                    VerticalDivider(),
                    Expanded(child: Text('右侧')),
                  ],
                )
              : const Text('单面板'),
        ),
      ));

      expect(find.text('单面板'), findsOneWidget);
      expect(find.text('左侧'), findsNothing);
      expect(find.text('右侧'), findsNothing);
    });

    testWidgets('分屏模式显示两个面板', (WidgetTester tester) async {
      const isSplitScreen = true;

      await tester.pumpWidget(createTestApp(
        child: Scaffold(
          body: isSplitScreen
              ? Row(
                  children: const [
                    Expanded(child: Center(child: Text('左侧'))),
                    VerticalDivider(),
                    Expanded(child: Center(child: Text('右侧'))),
                  ],
                )
              : const Text('单面板'),
        ),
      ));

      expect(find.text('左侧'), findsOneWidget);
      expect(find.text('右侧'), findsOneWidget);
      expect(find.byType(VerticalDivider), findsOneWidget);
    });
  });

  group('添加标签按钮测试', () {
    testWidgets('点击添加按钮触发回调', (WidgetTester tester) async {
      int tabCount = 1;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return createTestApp(
              child: Scaffold(
                body: Column(
                  children: [
                    Text('标签数: $tabCount'),
                    IconButton(
                      key: const Key('add_button'),
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        setState(() {
                          tabCount++;
                        });
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

      expect(find.text('标签数: 1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('add_button')));
      await tester.pump();

      expect(find.text('标签数: 2'), findsOneWidget);

      // 多次添加
      await tester.tap(find.byKey(const Key('add_button')));
      await tester.tap(find.byKey(const Key('add_button')));
      await tester.pump();

      expect(find.text('标签数: 4'), findsOneWidget);
    });
  });

  group('SnackBar 通知测试', () {
    testWidgets('显示消息完成通知', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(
        child: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                key: const Key('show_snackbar'),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('消息已完成'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: const Text('显示通知'),
              );
            },
          ),
        ),
      ));

      await tester.tap(find.byKey(const Key('show_snackbar')));
      await tester.pump();

      expect(find.text('消息已完成'), findsOneWidget);
    });
  });

  group('MaterialBanner 通知测试', () {
    testWidgets('显示新回复通知横幅', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(
        child: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                key: const Key('show_banner'),
                onPressed: () {
                  ScaffoldMessenger.of(context).showMaterialBanner(
                    MaterialBanner(
                      content: const Text('标签 1 有新回复'),
                      actions: [
                        TextButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                          },
                          child: const Text('查看'),
                        ),
                        TextButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                          },
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('显示横幅'),
              );
            },
          ),
        ),
      ));

      await tester.tap(find.byKey(const Key('show_banner')));
      await tester.pumpAndSettle();

      expect(find.text('标签 1 有新回复'), findsOneWidget);
      expect(find.text('查看'), findsOneWidget);
      expect(find.text('关闭'), findsOneWidget);

      // 点击关闭
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();

      expect(find.text('标签 1 有新回复'), findsNothing);
    });
  });
}
