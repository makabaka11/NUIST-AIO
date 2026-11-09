import 'package:flutter_test/flutter_test.dart';
import 'package:nuist_aio/src/services/sso_diagnostics.dart';

void main() {
  test('SSO diagnostic schema excludes credentials and identity payloads', () {
    final entry = SsoDiagnostics.entry(
      'campusCard',
      'navigation_blocked',
      location: Uri.parse(
        'https://USER:PASSWORD@icard.nuist.edu.cn/plat-pc/?ticket=SECRET_TICKET&synjones-auth=SECRET_JWT#SECRET_FRAGMENT',
      ),
      mainFrame: true,
    );
    expect(entry, contains('https://icard.nuist.edu.cn/plat-pc/'));
    for (final secret in [
      'USER',
      'PASSWORD',
      'SECRET_TICKET',
      'SECRET_JWT',
      'SECRET_FRAGMENT',
      'ticket=',
      'synjones-auth',
    ]) {
      expect(entry, isNot(contains(secret)));
    }
  });
}
