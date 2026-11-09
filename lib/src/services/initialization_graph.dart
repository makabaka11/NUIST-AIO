import 'site_registry.dart';

/// Runs independent sites together, and waits for authenticated dependencies.
/// Unverified/manual parents must already be ready; they are never auto-enabled.
Future<void> initializeSiteGraph({
  required Iterable<SchoolSite> sites,
  required Future<void> Function(SchoolSite) initialize,
  required bool Function(SchoolSiteId) ready,
  required void Function(SchoolSite) blocked,
}) async {
  final pending = {for (final site in sites) site.id: site};
  while (pending.isNotEmpty) {
    final batch = pending.values
        .where((site) => site.dependsOn.every((id) => !pending.containsKey(id)))
        .toList();
    if (batch.isEmpty) {
      throw StateError('Cyclic site initialization dependencies');
    }
    await Future.wait(
      batch.map((site) async {
        if (!site.dependsOn.every(ready)) {
          blocked(site);
          return;
        }
        await initialize(site);
      }),
    );
    for (final site in batch) {
      pending.remove(site.id);
    }
  }
}
