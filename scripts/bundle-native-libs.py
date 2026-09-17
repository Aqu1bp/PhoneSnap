#!/usr/bin/env python3
"""Copy and relocate the executable's complete native dependency graph into its .app."""
import json
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

app = Path(sys.argv[1]).resolve()
binary = app / 'Contents/MacOS/PhoneSnap'
frameworks = app / 'Contents/Frameworks'
licenses = app / 'Contents/Resources/ThirdPartyLicenses'
frameworks.mkdir(parents=True, exist_ok=True)
licenses.mkdir(parents=True, exist_ok=True)

def run(*args):
    return subprocess.check_output(args, text=True)

def dependencies(path):
    return [line.strip().split(' (compatibility version')[0] for line in run('otool', '-L', str(path)).splitlines()[1:]]

def system(path):
    return path.startswith(('/System/', '/usr/lib/'))

pending = [binary]
relocations = {}
manifest = []
while pending:
    target = pending.pop()
    changes = []
    for old in dependencies(target):
        if system(old):
            continue
        if old.startswith('@'):
            raise RuntimeError('Unexpected unresolved dependency: ' + old)
        source = Path(old).resolve()
        if not source.is_file():
            raise RuntimeError('Missing library: ' + old)
        destination = frameworks / Path(old).name
        if destination.name not in relocations:
            relocations[destination.name] = source
            shutil.copy2(source, destination)
            destination.chmod(0o755)
            pending.append(destination)
            # Homebrew keeps upstream license texts beside each package's lib directory.
            package = source.parent.parent
            copied = []
            for name in ('COPYING', 'COPYING.LESSER', 'LICENSE', 'LICENSE.txt'):
                license_file = package / name
                if license_file.is_file():
                    output = licenses / (package.parent.name + '-' + name)
                    shutil.copy2(license_file, output)
                    copied.append(output.name)
            if not copied:
                raise RuntimeError('Missing license texts for ' + str(source))
            manifest.append({'library': destination.name, 'package': package.parent.name,
                             'version': package.name, 'licenses': copied})
        elif relocations[destination.name] != source:
            raise RuntimeError('Library name collision: ' + destination.name)
        # otool lists the dylib's own ID as well as its dependencies.
        if target != binary and destination == target:
            continue
        relative = ('@executable_path/../Frameworks/' if target == binary else '@loader_path/') + destination.name
        changes.extend(['-change', old, relative])
    if target != binary:
        changes.extend(['-id', '@rpath/' + target.name])
    if changes:
        subprocess.run(['install_name_tool', *changes, str(target)], check=True, capture_output=True)

minimum = (13, 0)
for target in [binary, *sorted(frameworks.glob('*.dylib'))]:
    load_commands = run('otool', '-l', str(target))
    for value in re.findall(r'\bminos\s+(\d+(?:\.\d+)+)', load_commands):
        minimum = max(minimum, tuple(map(int, value.split('.'))))
    for value in re.findall(r'cmd LC_VERSION_MIN_MACOSX\s+cmdsize \d+\s+version (\d+(?:\.\d+)+)', load_commands):
        minimum = max(minimum, tuple(map(int, value.split('.'))))
    for dependency in dependencies(target):
        if not system(dependency) and not dependency.startswith(('@loader_path/', '@rpath/', '@executable_path/')):
            raise RuntimeError('Unbundled dependency: ' + dependency)

info = app / 'Contents/Info.plist'
with info.open('rb') as f:
    settings = plistlib.load(f)
settings['LSMinimumSystemVersion'] = '.'.join(map(str, minimum))
with info.open('wb') as f:
    plistlib.dump(settings, f)
(licenses / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
(licenses / 'README.txt').write_text('PhoneSnap dynamically links these unmodified upstream libraries.\n'
    'Source projects: https://github.com/libimobiledevice and https://github.com/openssl/openssl\n'
    'Package versions are listed in manifest.json; license texts are included here.\n'
    'Build dependencies can be replaced and the app rebuilt using the public PhoneSnap source and scripts.\n')
for library in sorted(frameworks.glob('*.dylib')):
    subprocess.run(['codesign', '--force', '--sign', '-', str(library)], check=True, capture_output=True)
subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True, capture_output=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print(f'Bundled {len(relocations)} native libraries; minimum macOS {settings["LSMinimumSystemVersion"]}; no external library paths.')
