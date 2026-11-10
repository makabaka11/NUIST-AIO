import '../campus_ui.dart';
import '../app_state.dart' show UiStyle;
import '../ui_style_scope.dart';
import 'material_about_page.dart';
import 'miuix_about_page.dart';

/// 只共享资料与操作，两套页面分别实现自己的视觉语言。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext context) =>
      UiStyleScope.of(context) == UiStyle.miuix
      ? const MiuixAboutPage()
      : const MaterialAboutPage();
}
