import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/site_registry.dart';

class PublicHolidayDay {
  const PublicHolidayDay(this.date, this.name, this.holiday);
  final String date, name;
  final bool holiday;

  static List<PublicHolidayDay> parse(dynamic response, int year) {
    if (response is! Map ||
        response['code'] != 0 ||
        response['data'] is! List) {
      throw const FormatException('节假日数据不可用');
    }
    final rows = response['data'] as List;
    if (rows.isEmpty || rows.length > 366) {
      throw const FormatException('节假日数据不完整');
    }
    final seen = <String>{};
    return rows.map((row) {
      if (row is! Map) throw const FormatException('节假日格式无效');
      final date = row['date'], name = row['name'], type = row['type'];
      final parsed =
          date is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)
          ? DateTime.tryParse('${date}T00:00:00Z')
          : null;
      if (parsed == null ||
          parsed.year != year ||
          parsed.toIso8601String().substring(0, 10) != date ||
          !seen.add(date as String) ||
          name is! String ||
          name.trim().isEmpty ||
          name.length > 40 ||
          !{'holiday', 'workday'}.contains(type)) {
        throw const FormatException('节假日字段无效');
      }
      return PublicHolidayDay(date, name, type == 'holiday');
    }).toList();
  }
}

class PublicHolidayRepository {
  PublicHolidayRepository({this.request});
  final Future<dynamic> Function(int year)? request;
  final _prefs = SharedPreferencesAsync();

  Future<dynamic> _download(int year) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      return await (() async {
        final req = await client.getUrl(PublicHolidaySource.year(year));
        req.followRedirects = false;
        req.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await req.close();
        if (response.statusCode != 200) {
          throw const FormatException('节假日服务暂不可用');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 128 * 1024) throw const FormatException('节假日数据过大');
        }
        return jsonDecode(utf8.decode(bytes));
      })().timeout(const Duration(seconds: 5));
    } finally {
      client.close(force: true);
    }
  }

  /// Only public dates are cached. Errors leave the previous valid year usable.
  Future<List<PublicHolidayDay>> load(int year) async {
    final key = '${PublicHolidaySource.id}.$year.v1';
    List<PublicHolidayDay> cached = const [];
    try {
      final raw = await _prefs.getString(key);
      if (raw != null) {
        final saved = jsonDecode(raw) as Map;
        cached = PublicHolidayDay.parse(saved['response'], year);
        final age = DateTime.now().difference(
          DateTime.parse(saved['savedAt'] as String),
        );
        if (!age.isNegative && age < const Duration(days: 7)) return cached;
      }
    } catch (_) {
      /* Invalid cache is ignored. */
    }
    try {
      final response = await (request ?? _download)(year);
      final days = PublicHolidayDay.parse(response, year);
      try {
        await _prefs.setString(
          key,
          jsonEncode({
            'savedAt': DateTime.now().toIso8601String(),
            'response': response,
          }),
        );
      } catch (_) {
        /* Persistence failure does not discard a valid response. */
      }
      return days;
    } catch (_) {
      return cached;
    }
  }
}
