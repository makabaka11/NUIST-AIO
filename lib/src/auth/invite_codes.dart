import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 内测邀请码校验。
///
/// 软件内只编译 10 个邀请码的 SHA-256 摘要（防止从二进制中直接提取明文），
/// 明文清单仅保存在仓库 docs/invite-codes.txt 中，供内测分发使用。
/// 输入会先规范化：去掉空格与连字符并转为大写，因此大小写、有无分隔符
/// 均可识别。校验纯本地完成，无需联网。
const List<String> _inviteCodeDigests = [
  '967736ca6fb925da958937f9e3da2b87c87ff216ea88ad866de6676de665bef2',
  '8c6b68348f422059c724f7aab69c3d59118c21a6e13e7169c4e317f1615d9e99',
  '80a19d1f6942497477e138e2614033108e5c4e85058d194c967da211df5668c9',
  '1eb75734d23ed55d8c50bff70c762fe05ba1b55002d99c147e071f2fe5d25b8f',
  '071151c046ddf12a36b66dca7b87a688926ed4c240324f894aee09c1c94e2950',
  '37da666d79091fe9dd734a027e951f3fa12fadc0a9bad4d8b4de471b61c0d9ef',
  '59a1cd59bda4d61072b730e18dd5d953506a0902da3d6877dd68bc38df9e222e',
  'da5750fdefa91bbf168776174cd56a4b6fe5bee407a2d3f45b445126e15801d8',
  '42ca921871d22f47890dbb78dd6a650c02988cd87812d5d2cbbb081fd53e3c61',
  '66dddc5c77870a181e93e8e22cc2b03616a191f4810c9ca8eabab457406a68fd',
];

const inviteCodeLength = 16;

/// 去掉空格与连字符并转为大写。
String normalizeInviteCode(String input) =>
    input.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

bool isValidInviteCode(String input) {
  final normalized = normalizeInviteCode(input);
  if (normalized.length != inviteCodeLength) return false;
  final digest = sha256.convert(utf8.encode(normalized)).toString();
  return _inviteCodeDigests.contains(digest);
}
