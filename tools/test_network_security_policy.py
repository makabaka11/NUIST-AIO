"""Security invariants for the explicitly approved, host-scoped card workaround."""
import base64,json,subprocess,unittest,xml.etree.ElementTree as ET
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class NetworkPolicyTest(unittest.TestCase):
    def test_scope_and_pins_are_fail_closed(self):
        root=ET.parse(ROOT/'android/app/src/main/res/xml/network_security_config.xml').getroot()
        base=root.find('base-config');self.assertEqual(base.get('cleartextTrafficPermitted'),'false')
        self.assertEqual([c.get('src') for c in base.findall('trust-anchors/certificates')],['system'])
        configs=root.findall('domain-config');self.assertEqual(len(configs),1)
        config=configs[0];self.assertEqual(config.get('cleartextTrafficPermitted'),'false')
        domains=config.findall('domain');self.assertEqual(len(domains),1)
        self.assertEqual(domains[0].text,'icard.nuist.edu.cn');self.assertEqual(domains[0].get('includeSubdomains'),'false')
        anchors=config.findall('trust-anchors/certificates');self.assertEqual({a.get('src') for a in anchors},{'system','@raw/nuist_xcc_intermediate'})
        self.assertEqual(next(a for a in anchors if a.get('src').startswith('@raw')).get('overridePins'),'false')
        pins=config.find('pin-set');self.assertNotIn('expiration',pins.attrib)
        values=pins.findall('pin');self.assertEqual(len(values),1);self.assertEqual(values[0].get('digest'),'SHA-256')
        policy=json.loads((ROOT/'assets/data/nuist_icard_tls_policy.json').read_text())
        self.assertTrue(policy['userApproved']);self.assertEqual(values[0].text,policy['spkiSHA256'])
        self.assertEqual(len(base64.b64decode(values[0].text,validate=True)),32)
        self.assertIsNone(root.find('debug-overrides'))
    def test_manifest_and_ca_resource(self):
        android='{http://schemas.android.com/apk/res/android}'
        app=ET.parse(ROOT/'android/app/src/main/AndroidManifest.xml').getroot().find('application')
        self.assertEqual(app.get(android+'networkSecurityConfig'),'@xml/network_security_config')
        self.assertEqual(app.get(android+'usesCleartextTraffic'),'false')
        cert=(ROOT/'android/app/src/main/res/raw/nuist_xcc_intermediate.pem').read_bytes()
        self.assertEqual(cert.count(b'BEGIN CERTIFICATE'),1)
        text=subprocess.run(['/usr/bin/openssl','x509','-noout','-text'],input=cert,capture_output=True,check=True).stdout
        self.assertIn(b'CA:TRUE',text)
        self.assertIn(b'Xcc Trust OV SSL CA',text)
        for source in (ROOT/'lib').rglob('*.dart'):
            self.assertNotIn('ServerTrustAuthResponseAction.PROCEED',source.read_text())
if __name__=='__main__':unittest.main()
