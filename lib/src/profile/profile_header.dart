import '../campus_ui.dart';

import '../app_state.dart';

const avatarColors = [
  Color(0xff405d85),
  Color(0xff6e4c86),
  Color(0xff8b465a),
  Color(0xff4b6a4d),
  Color(0xff876038),
  Color(0xff426b70),
  Color(0xff665b91),
  Color(0xff8b5044),
  Color(0xff526582),
  Color(0xff726044),
];
String avatarLetters(String name) {
  final letters = name.trim().characters;
  return letters.isEmpty
      ? '同学'
      : letters.skip(letters.length > 2 ? letters.length - 2 : 0).toString();
}

class ProfileHeader extends StatefulWidget {
  const ProfileHeader({super.key, required this.state, required this.onLogin});
  final AppState state;
  final VoidCallback onLogin;
  @override
  State<ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<ProfileHeader> {
  bool picking = false;
  Future<void> pick() async {
    if (picking) return;
    setState(() => picking = true);
    try {
      await widget.state.chooseAvatar();
    } on FormatException catch (e) {
      if (mounted) {
        showCampusSnackBar(context, SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        showCampusSnackBar(
          context,
          const SnackBar(content: Text('无法选择图片，请检查照片权限或换一张图片。')),
        );
      }
    }
    if (mounted) setState(() => picking = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state,
        profile = state.studentProfile,
        colors = Theme.of(context).colorScheme;
    final name = profile?.name ?? state.displayName ?? '南信同学';
    final bg = avatarColors[state.avatarColor % avatarColors.length];
    final letters = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        avatarLetters(name),
        maxLines: 1,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final avatar = Semantics(
      container: true,
      button: true,
      label: '更换本地头像',
      child: Tooltip(
        message: '从相册选择本地头像',
        child: InkWell(
          onTap: picking ? null : pick,
          customBorder: const CircleBorder(),
          child: Stack(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: bg,
                child: state.avatarBytes == null
                    ? letters
                    : ClipOval(
                        child: Image.memory(
                          state.avatarBytes!,
                          key: ValueKey(state.avatarBytes),
                          width: 68,
                          height: 68,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => letters,
                        ),
                      ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: CircleAvatar(
                  radius: 11,
                  backgroundColor: colors.surface,
                  child: picking
                      ? const InlineLoadingIndicator(size: 14)
                      : Icon(
                          Icons.photo_camera_outlined,
                          size: 14,
                          color: colors.primary,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Card(
      semanticContainer: false,
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                avatar,
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 6),
                      LoadingText(
                        profile == null
                            ? (state.connectedAt == null
                                  ? '连接校园账号后显示学生资料'
                                  : '${state.syncingProfile ? '正在读取' : '尚未同步'}学生资料')
                            : '学号 ${profile.studentNumber}',
                        loading: state.syncingProfile,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (profile != null) ...[
              const SizedBox(height: 16),
              for (final info in [
                ('学院', profile.college),
                ('专业', profile.major),
                ('年级', profile.grade),
                ('班级', profile.className),
              ])
                if (info.$2.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('${info.$1}  ${info.$2}'),
                  ),
            ],
            if (state.profileNotice != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  state.profileNotice!,
                  style: TextStyle(color: colors.error),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: widget.onLogin,
                  icon: const Icon(Icons.link),
                  label: Text(state.connectedAt == null ? '连接校园账号' : '重新连接'),
                ),
                if (state.connectedAt != null)
                  TextButton.icon(
                    onPressed: state.syncingProfile
                        ? null
                        : state.syncStudentProfile,
                    icon: state.syncingProfile
                        ? const InlineLoadingIndicator()
                        : const Icon(Icons.refresh),
                    label: Text(state.syncingProfile ? '正在同步…' : '更新资料'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
