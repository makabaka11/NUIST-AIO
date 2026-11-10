import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/service_sessions.dart';
import '../services/site_registry.dart';

class NativeLibrarySession extends NativeServiceSession {
  NativeLibrarySession()
    : super(
        site: SchoolSites.get(SchoolSiteId.library),
        connectionTimeout: const Duration(seconds: 25),
      );
  @override
  Future<void> close() async {
    await super.close();
    if (!available) return;
    final manager = CookieManager.instance();
    for (final path in [
      '/meta-local/opac/users/loans',
      '/space/reader/lendList',
    ]) {
      final url = WebUri('https://elib.nuist.edu.cn$path');
      for (final cookie in await manager.getCookies(url: url)) {
        await manager.deleteCookie(
          url: url,
          name: cookie.name,
          domain: cookie.domain,
          path: cookie.path ?? '/',
        );
      }
    }
  }
}

class LibraryBook {
  LibraryBook.fromJson(Map<String, dynamic> j)
    : title = j['title'] as String,
      author = j['author'] as String,
      loanDate = j['loanDate'] as String,
      dueDate = j['dueDate'] as String,
      status = j['status'] as String;
  final String title, author, loanDate, dueDate, status;
  Map<String, dynamic> toJson() => {
    'title': title,
    'author': author,
    'loanDate': loanDate,
    'dueDate': dueDate,
    'status': status,
  };
  bool overdue(DateTime today) {
    if (status == 'overdue') return true;
    final due = DateTime.tryParse(dueDate);
    return due != null &&
        due.isBefore(DateTime(today.year, today.month, today.day));
  }
}

class LibraryLoans {
  LibraryLoans(this.books, this.updatedAt);
  final List<LibraryBook> books;
  final DateTime updatedAt;
  factory LibraryLoans.fromJson(Map<String, dynamic> j) => LibraryLoans(
    (j['books'] as List)
        .map((e) => LibraryBook.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    DateTime.parse(j['updatedAt'] as String),
  );
  Map<String, dynamic> toJson() => {
    'books': books.map((b) => b.toJson()).toList(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}
