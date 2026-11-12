import 'package:flutter_test/flutter_test.dart';
import 'package:nuist_aio/src/services/site_registry.dart';
import 'package:nuist_aio/src/services/initialization_graph.dart';

void main() {
  SchoolSite example(SchoolSiteId id, List<SchoolSiteId> dependencies) =>
      SchoolSite(
        id: id,
        label: id.name,
        auth: SiteAuth.casCookies,
        host: 'example.test',
        entry: Uri.https('example.test', '/'),
        features: const [],
        dependsOn: dependencies,
        credentialRule: 'synthetic',
        renewalRule: 'synthetic',
      );
  test(
    'initialization waits for parent sites even when the child is listed first',
    () async {
      final ready = <SchoolSiteId>{SchoolSiteId.portal},
          order = <SchoolSiteId>[];
      await initializeSiteGraph(
        sites: [
          example(SchoolSiteId.library, [SchoolSiteId.teaching]),
          example(SchoolSiteId.teaching, [SchoolSiteId.portal]),
        ],
        ready: ready.contains,
        blocked: (_) => fail('unexpected dependency failure'),
        initialize: (site) async {
          order.add(site.id);
          ready.add(site.id);
        },
      );
      expect(order, [SchoolSiteId.teaching, SchoolSiteId.library]);
    },
  );
  test('a failed parent blocks its child while an independent site still initializes', () async {
    final ready = <SchoolSiteId>{SchoolSiteId.portal},
        blocked = <SchoolSiteId>[];
    await initializeSiteGraph(
      sites: [
        example(SchoolSiteId.library, [SchoolSiteId.teaching]),
        example(SchoolSiteId.teaching, [SchoolSiteId.portal]),
        example(SchoolSiteId.campusCard, [SchoolSiteId.portal]),
      ],
      ready: ready.contains,
      blocked: (site) => blocked.add(site.id),
      initialize: (site) async {
        if (site.id != SchoolSiteId.teaching) ready.add(site.id);
      },
    );
    expect(ready, contains(SchoolSiteId.campusCard));
    expect(blocked, [SchoolSiteId.library]);
  });
  test(
    'invalid dependency cycles fail instead of hanging the wizard',
    () async {
      await expectLater(
        initializeSiteGraph(
          sites: [
            example(SchoolSiteId.teaching, [SchoolSiteId.library]),
            example(SchoolSiteId.library, [SchoolSiteId.teaching]),
          ],
          ready: (_) => false,
          blocked: (_) {},
          initialize: (_) async {},
        ),
        throwsStateError,
      );
    },
  );

  test(
    'business probes cannot run on CAS callbacks or an unloaded document URL',
    () {
      final card = SchoolSites.get(SchoolSiteId.campusCard);
      for (final url in [
        SchoolSites.get(SchoolSiteId.campusCard).entry!,
        Uri.parse('https://authserver.nuist.edu.cn/authserver/login'),
        Uri.parse('about:blank'),
        Uri.parse('http://icard.nuist.edu.cn/plat-pc/'),
        Uri.parse('https://icard.nuist.edu.cn/plat-pc-fake/'),
      ]) {
        expect(card.acceptsProbeLocation(url), isFalse);
      }
      expect(
        card.acceptsProbeLocation(
          Uri.parse('https://icard.nuist.edu.cn/plat-pc/businesslobby'),
        ),
        isTrue,
      );
      expect(
        card.acceptsProbeLocation(
          Uri.parse('https://icard.nuist.edu.cn/plat-pc'),
        ),
        isTrue,
      );
      expect(
        SchoolSites.get(SchoolSiteId.teaching)
            .acceptsProbeLocation(SchoolSites.get(SchoolSiteId.teaching).entry),
        isTrue,
      );
    },
  );

  test('each integration has a unique ID, declared dependencies and credential rules', () {
    final ids = SchoolSites.all.map((s) => s.id).toSet();
    expect(ids.length, SchoolSites.all.length);
    final features = <String>{};
    for (final site in SchoolSites.all) {
      expect(site.host, isNotEmpty);
      expect(site.credentialRule, isNotEmpty);
      expect(site.renewalRule, isNotEmpty);
      for (final dep in site.dependsOn) {
        expect(ids, contains(dep));
      }
      if (site.entry != null) {
        expect(
          site.entry!.scheme,
          site.browserOnly ? isIn(['https', 'http']) : 'https',
        );
        expect(site.entry!.host, site.host);
      }
      for (final feature in site.features) {
        expect(
          features.add(feature.id),
          isTrue,
          reason: 'Duplicate feature ${feature.id}',
        );
        if (feature.implemented && !site.browserOnly && !feature.browserOnly) {
          expect(site.auth, isNot(SiteAuth.unverified));
        }
        if (feature.entry != null) {
          expect(Uri.parse(feature.entry!).host, site.host);
          if (!site.browserOnly && !feature.browserOnly) {
            expect(site.navigation!(Uri.parse(feature.entry!)), isTrue);
            expect(feature.readySelector, isNotEmpty);
          }
        }
      }
      if (site.browserOnly) {
        expect(site.asset, isNull);
        expect(site.probeTask, isNull);
        expect(site.navigation, isNull);
        expect(site.automatic, false);
      }
      if (site.auth == SiteAuth.unverified) expect(site.automatic, isFalse);
      if (site.automatic) {
        expect(site.entry, isNotNull);
        expect(site.navigation!(site.entry), isTrue);
        if (site.auth == SiteAuth.nativeCookies) {
          expect(site.id, SchoolSiteId.chaoxing);
          expect(site.dependsOn, isEmpty);
        } else {
          expect(site.dependsOn, contains(SchoolSiteId.portal));
        }
        expect(site.asset, startsWith('assets/js/'));
        expect(site.probeTask, isNotEmpty);
        expect(site.probePrefixes, isNotEmpty);
      }
    }
    expect(
      features,
      containsAll([
        'profile',
        'calendar',
        'schedule',
        'rooms',
        'grades',
        'exams',
        'wallet',
        'bills',
        'power_main',
        'power_qin',
        'power_jnh',
        'library_search',
        'library_loans',
      ]),
    );
    void visit(SchoolSiteId id, Set<SchoolSiteId> chain) {
      expect(
        chain.contains(id),
        isFalse,
        reason: 'Cyclic authentication dependency',
      );
      for (final dep in SchoolSites.get(id).dependsOn) {
        visit(dep, {...chain, id});
      }
    }

    for (final id in ids) {
      visit(id, {});
    }
  });
  test('a token string alone never satisfies the card readiness rule', () {
    final site = SchoolSites.get(SchoolSiteId.campusCard);
    expect(site.isReady({'ok': true}), isFalse);
    expect(site.isReady({'ok': true, 'ready': false}), isFalse);
    expect(site.isReady({'ok': true, 'ready': true}), isTrue);
    expect(site.isReady({'ok': false, 'ready': true}), isFalse);
  });
}
