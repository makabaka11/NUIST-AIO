import 'package:flutter_test/flutter_test.dart';
import 'package:nuist_aio/src/services/navigation.dart';

void main() {
  test(
    'known HTTP CAS redirects reload the same path and parameters over HTTPS',
    () {
      final original = Uri.parse(
        'http://authserver.nuist.edu.cn/authserver/login?service=https%3A%2F%2Ficard.nuist.edu.cn%2Fberserker-auth%2Fcas%2Flogin%2Fwisedu',
      );
      final secure = SchoolNavigation.httpsUpgrade(
        original,
        SchoolNavigation.card,
      )!;
      expect(secure.scheme, 'https');
      expect(secure.host, original.host);
      expect(secure.path, original.path);
      expect(secure.query, original.query);
      expect(secure.port, 443);
      expect(
        SchoolNavigation.httpsUpgrade(
          Uri.parse('http://authserver.nuist.edu.cn:80/authserver/login'),
          SchoolNavigation.card,
        )!.port,
        443,
      );
      expect(SchoolNavigation.card(original), isFalse);
      expect(SchoolNavigation.card(secure), isTrue);
    },
  );
  test('upgrades never admit foreign hosts, userinfo, custom ports or payment pages', () {
    for (final url in [
      'http://evil.test/authserver/login',
      'http://authserver.nuist.edu.cn.evil.test/authserver/login',
      'http://u:p@authserver.nuist.edu.cn/authserver/login',
      'http://authserver.nuist.edu.cn:8080/authserver/login',
      'http://icard.nuist.edu.cn/charge/order/add',
      'http://icard.nuist.edu.cn/charge-pc/pays/448',
      'https://authserver.nuist.edu.cn/authserver/login',
      'javascript:alert(1)',
    ]) {
      expect(
        SchoolNavigation.httpsUpgrade(Uri.parse(url), SchoolNavigation.card),
        isNull,
        reason: url,
      );
    }
  });
}
