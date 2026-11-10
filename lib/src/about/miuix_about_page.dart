import 'package:flutter_miuix/miuix.dart';

import '../campus_ui.dart';
import 'about_actions.dart';

/// 参考 HyperOS 关于页：独立的紫蓝渐变、大图标、文字箭头分组。
/// 直接使用 flutter_miuix 的顶栏、卡片和 ArrowPreference。
class MiuixAboutPage extends StatelessWidget {
  const MiuixAboutPage({super.key});
  @override
  Widget build(BuildContext context) {
    final dark = MiuixTheme.of(context).brightness == Brightness.dark;
    final foreground = dark ? const Color(0xfff4efff) : const Color(0xff28203d);
    final secondary = dark ? const Color(0xffb8a9d0) : const Color(0xff6b5d80);
    final accent = dark ? const Color(0xffb394ea) : const Color(0xff7654b3);
    final cardColor = dark ? const Color(0x664e3e70) : const Color(0x99ffffff);
    final heroHeight = (MediaQuery.sizeOf(context).height * .49).clamp(
      340.0,
      480.0,
    );
    final titleColors = MiuixBasicComponentColors(
      color: foreground,
      disabledColor: secondary,
    );
    final summaryColors = MiuixBasicComponentColors(
      color: secondary,
      disabledColor: secondary,
    );
    Widget row(String title, VoidCallback onClick, {String? summary}) =>
        MiuixArrowPreference(
          title: title,
          summary: summary,
          onClick: onClick,
          titleColor: titleColors,
          summaryColor: summaryColors,
          insideMargin: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 20,
          ),
        );
    Widget group(List<Widget> children) => MiuixCard(
      cornerRadius: 26,
      colors: MiuixCardColors(color: cardColor, contentColor: foreground),
      child: Column(children: children),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: dark
              ? const [Color(0xff100d1d), Color(0xff301c46), Color(0xff181d5c)]
              : const [Color(0xfff7f4fc), Color(0xffeee2f5), Color(0xffe0e6ff)],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: MiuixSmallTopAppBar(
            title: '',
            color: Colors.transparent,
            navigationIcon: Tooltip(
              message: MaterialLocalizations.of(context).backButtonTooltip,
              child: MiuixIconButton(
                onPressed: () => Navigator.maybePop(context),
                child: Icon(
                  Icons.arrow_back_ios_new,
                  color: foreground,
                  size: 24,
                ),
              ),
            ),
          ),
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
              children: [
                SizedBox(
                  height: heroHeight,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ClipPath(
                        clipper: ShapeBorderClipper(
                          shape: MiuixSquircleBorder(cornerRadius: 28),
                        ),
                        child: Image.asset(
                          'assets/branding/app_icon.png',
                          width: 112,
                          height: 112,
                          semanticLabel: '信大AIO应用图标',
                        ),
                      ),
                      const SizedBox(height: 28),
                      MiuixText(
                        '信大 AIO',
                        fontSize: 36,
                        color: accent,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      MiuixText(
                        appVersionLabel,
                        fontSize: 16,
                        color: secondary,
                      ),
                    ],
                  ),
                ),
                group([
                  row(
                    '交流与反馈',
                    () => AboutActions.feedback(context),
                    summary: '信大AIO交流群 · 1135530515',
                  ),
                  row(
                    '关于信大 AIO',
                    () => AboutActions.introduction(context),
                    summary: '国危思良将。',
                  ),
                  row('开源许可', () => showCampusLicenses(context)),
                ]),
                const SizedBox(height: 16),
                group([
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: MiuixText('开发者', fontSize: 14, color: secondary),
                    ),
                  ),
                  row(
                    'Retr0',
                    () => AboutActions.developer(context),
                    summary: 'www.retr0.xyz',
                  ),
                  row(
                    '联系邮箱',
                    () => AboutActions.email(context),
                    summary: 'ded000@retr0.xyz',
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
