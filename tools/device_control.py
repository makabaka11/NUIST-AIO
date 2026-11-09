"""Task-local ADB UI helper; user explicitly authorized ADB on this test phone."""
import argparse, os, re, shutil, subprocess, xml.etree.ElementTree as ET
from pathlib import Path
sdk = os.environ.get('ANDROID_SDK_ROOT') or os.environ.get('ANDROID_HOME')
if not sdk and Path('android/local.properties').exists():
    sdk = next((line.split('=', 1)[1] for line in Path('android/local.properties').read_text().splitlines() if line.startswith('sdk.dir=')), None)
adb = os.environ.get('ADB') or shutil.which('adb') or (str(Path(sdk) / 'platform-tools/adb') if sdk else None)
if not adb: raise SystemExit('Set ADB or ANDROID_SDK_ROOT')
serial = os.environ.get('NUIST_TEST_DEVICE')
if not serial:
    devices = [line.split()[0] for line in subprocess.check_output([adb, 'devices'], text=True).splitlines()[1:] if line.strip().endswith('device')]
    if len(devices) != 1: raise SystemExit('Set NUIST_TEST_DEVICE explicitly when there is not exactly one ready device')
    serial = devices[0]
ADB = [adb, '-s', serial]
def run(*args):
    return subprocess.check_output(ADB + list(args))
def ensure_app():
    activity = run('shell', 'dumpsys', 'activity', 'activities').decode()
    resumed = [line for line in activity.splitlines() if 'topResumedActivity=' in line]
    if not resumed or 'com.retrsoft.nuistaio/' not in resumed[0]:
        raise SystemExit('Stop: the campus app is not the foreground activity')
def tree():
    ensure_app()
    run('shell', 'uiautomator', 'dump', '/data/local/tmp/nuistaio-ui.xml')
    raw = run('shell', 'cat', '/data/local/tmp/nuistaio-ui.xml')
    run('shell', 'rm', '/data/local/tmp/nuistaio-ui.xml')
    return ET.fromstring(raw)
p = argparse.ArgumentParser(); p.add_argument('action', choices=['tap', 'labels', 'screen', 'back']); p.add_argument('value', nargs='?'); args = p.parse_args()
if args.action in {'tap', 'labels'} and not args.value: p.error('A non-empty control label prefix is required')
if args.action == 'screen':
    ensure_app()
    path = Path('build/device-validation/current.png');path.write_bytes(run('exec-out', 'screencap', '-p'));os.chmod(path, 0o600);print(path)
elif args.action == 'back':
    tree();run('shell', 'input', 'keyevent', '4')
else:
    nodes = tree().iter('node');found = False
    for node in nodes:
        if node.get('password') == 'true': continue
        text = node.get('text') or node.get('content-desc', '')
        if not text.startswith(args.value or ''): continue
        if args.action == 'labels':
            print(text[:300], node.get('bounds'));continue
        points = list(map(int, re.findall(r'\d+', node.get('bounds', ''))))
        if len(points) == 4:
            run('shell', 'input', 'tap', str((points[0]+points[2])//2), str((points[1]+points[3])//2));print('Tapped requested control');found=True;break
    if args.action == 'tap' and not found: raise SystemExit('Requested control not present')
