"""Split a universal macOS app, including embedded frameworks, into signed archives."""
from pathlib import Path
import subprocess
import sys
import tempfile


def package(app, destination, tag):
    app = Path(app).resolve()
    destination = Path(destination).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    for arch in ('arm64', 'x86_64'):
        with tempfile.TemporaryDirectory() as directory:
            thin = Path(directory) / app.name
            subprocess.run(['ditto', str(app), str(thin)], check=True)
            for file in thin.rglob('*'):
                if file.is_symlink() or not file.is_file():
                    continue
                kind = subprocess.run(['file', '-b', str(file)], check=True,
                                      capture_output=True, text=True).stdout
                if 'Mach-O' in kind:
                    architectures = subprocess.run(['lipo', '-archs', str(file)], check=True,
                                                   capture_output=True, text=True).stdout.split()
                    if arch not in architectures:
                        raise ValueError(f'Missing {arch} in {file.name}: {architectures}')
                    if architectures != [arch]:
                        output = file.with_name(file.name + '.thin')
                        subprocess.run(['lipo', str(file), '-thin', arch, '-output', str(output)],
                                       check=True)
                        output.chmod(file.stat().st_mode)
                        output.replace(file)
                    actual = subprocess.run(['lipo', '-archs', str(file)], check=True,
                                            capture_output=True, text=True).stdout.split()
                    if actual != [arch]:
                        raise ValueError(f'Unexpected architectures in {file.name}: {actual}')
            # Refresh signatures after modifying the app and its nested frameworks.
            subprocess.run(['codesign', '--force', '--deep', '--sign', '-',
                            '--preserve-metadata=entitlements', str(thin)], check=True)
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(thin)], check=True)
            subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent',
                            str(thin), str(destination / f'nuistaio-{tag}-macos-{arch}.zip')],
                           check=True)


if __name__ == '__main__':
    package(*sys.argv[1:])
