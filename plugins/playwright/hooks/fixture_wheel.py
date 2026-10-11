"""Build the fixture wheel for install-python-deps.test.sh: a pure-python wheel providing the numpy and PIL
modules pydeps.py probes, so the hook's install runs end to end with no package index.

usage: python fixture_wheel.py DIR   -> writes the wheel into DIR, prints its sha256
"""
import base64
import hashlib
import sys
import zipfile
from pathlib import Path

NAME, VERSION = 'fakedeps', '1.0'
MODULES = {'numpy/__init__.py': 'VALUE = 42\n', 'PIL/__init__.py': 'VALUE = 7\n'}


def make_wheel(folder):
    dist = f'{NAME}-{VERSION}.dist-info'
    files = {
        **MODULES,
        f'{dist}/METADATA': f'Metadata-Version: 2.1\nName: {NAME}\nVersion: {VERSION}\n',
        f'{dist}/WHEEL': 'Wheel-Version: 1.0\nGenerator: test\nRoot-Is-Purelib: true\nTag: py3-none-any\n',
    }
    record = ''.join(
        f'{p},sha256={base64.urlsafe_b64encode(hashlib.sha256(c.encode()).digest()).rstrip(b"=").decode()},{len(c)}\n'
        for p, c in files.items()) + f'{dist}/RECORD,,\n'
    path = Path(folder) / f'{NAME}-{VERSION}-py3-none-any.whl'
    with zipfile.ZipFile(path, 'w') as z:
        for p, c in {**files, f'{dist}/RECORD': record}.items():
            z.writestr(p, c)
    return hashlib.sha256(path.read_bytes()).hexdigest()


if __name__ == '__main__':
    print(make_wheel(sys.argv[1]))
