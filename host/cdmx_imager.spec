# -*- mode: python ; coding: utf-8 -*-
from pathlib import Path
import sys

root = Path(SPECPATH).parent

a = Analysis(
    [str(root / "host" / "imager_app.py")],
    pathex=[str(root)],
    binaries=[],
    datas=[
        (str(root / "host" / "imager_ui.html"), "host"),
        (str(root / "site" / "manifest.json"), "site"),
    ],
    hiddenimports=["pyfatfs.PyFatFS", "pyfatfs.PyFat", "fs"],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name="CDMX-Radxa-Flasher",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    uac_admin=sys.platform == "win32",
)
