import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuist_aio/src/navigation/tab_pages.dart';

void main() {
  testWidgets(
    'MIUIX traverses pages in both directions and latest click wins',
    (tester) async {
      var selected = 0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return SizedBox(
                width: 400,
                child: TabPages(
                  index: selected,
                  horizontal: true,
                  onSelected: (index) => update(() => selected = index),
                  children: List.generate(
                    4,
                    (index) => Center(child: Text('page $index')),
                  ),
                ),
              );
            },
          ),
        ),
      );
      final width = tester.getSize(find.byType(TabPages)).width;
      update(() => selected = 3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final first = tester.getCenter(find.text('page 0'));
      final second = tester.getCenter(find.text('page 1'));
      expect(first.dx, lessThan(width / 2));
      expect(second.dx - first.dx, closeTo(width, 0.01));
      expect(
        tester
            .widget<FadeTransition>(find.byType(FadeTransition).last)
            .opacity
            .value,
        1,
      );
      await tester.pump(const Duration(milliseconds: 70));
      update(() => selected = 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      update(() => selected = 2);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('page 2').hitTestable(), findsOneWidget);
      expect(
        tester.getCenter(find.text('page 2')).dx,
        closeTo(width / 2, 0.01),
      );
      expect(selected, 2);
      update(() => selected = 0);
      await tester.pumpAndSettle();
      expect(find.text('page 0').hitTestable(), findsOneWidget);
    },
  );

  testWidgets(
    'swipes track the finger, synchronize selection, and keep edit/scroll state across styles',
    (tester) async {
      var selected = 0;
      var horizontal = true;
      late StateSetter update;
      final edits = TextEditingController();
      final scroll = ScrollController();
      addTearDown(edits.dispose);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return TabPages(
                index: selected,
                horizontal: horizontal,
                onSelected: (index) => update(() => selected = index),
                children: [
                  Material(
                    child: ListView(
                      controller: scroll,
                      children: [
                        TextField(controller: edits),
                        for (var i = 0; i < 30; i++)
                          SizedBox(height: 60, child: Text('row $i')),
                      ],
                    ),
                  ),
                  const Center(child: Text('second page')),
                  const Center(child: Text('third page')),
                ],
              );
            },
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '保留输入');
      FocusManager.instance.primaryFocus?.unfocus();
      scroll.jumpTo(180);
      await tester.pump();
      final width = tester.getSize(find.byType(TabPages)).width;
      final gesture = await tester.startGesture(Offset(width * .9, 450));
      await gesture.moveBy(const Offset(-24, 0));
      await tester.pump();
      await gesture.moveBy(Offset(-width * .65, 0));
      await tester.pump();
      expect(selected, 1);
      final x = tester.getCenter(find.text('second page')).dx;
      expect(x, greaterThan(width / 2));
      expect(x, lessThan(width * 1.5));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('second page').hitTestable(), findsOneWidget);
      await tester.drag(find.byType(TabPages), const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(
        selected,
        1,
        reason: 'A rejected horizontal gesture must not reset the tab',
      );
      update(() => horizontal = false);
      await tester.pumpAndSettle();
      update(() => selected = 0);
      await tester.pumpAndSettle();
      expect(edits.text, '保留输入');
      expect(scroll.offset, 180);
      await tester.drag(find.byType(TabPages), Offset(-width * .7, 0));
      await tester.pumpAndSettle();
      expect(
        selected,
        0,
        reason: 'MD3 retains its existing navigation interaction',
      );
      update(() => horizontal = true);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(TabPages), const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(
        selected,
        0,
        reason: 'Vertical content scrolling must not change tabs',
      );
      expect(scroll.offset, greaterThan(180));
    },
  );

  testWidgets('RTL swipe direction and reduce motion are honored', (
    tester,
  ) async {
    var selected = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: TabPages(
                  index: selected,
                  horizontal: true,
                  onSelected: (index) => update(() => selected = index),
                  children: const [
                    Center(child: Text('first')),
                    Center(child: Text('second')),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.drag(find.byType(TabPages), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(find.text('second').hitTestable(), findsOneWidget);
    update(() => selected = 0);
    await tester.pump();
    expect(find.text('first').hitTestable(), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
