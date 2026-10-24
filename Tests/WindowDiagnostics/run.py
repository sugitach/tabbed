#!/usr/bin/env python3
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='tabbed-diagnostics-') as directory:
 output=Path(directory)/'tests'
 subprocess.run(['/usr/bin/xcrun','swiftc','-swift-version','5','-target','arm64-apple-macosx14.0','-module-cache-path',directory+'/cache',str(root/'Sources/App/WindowDiagnostics.swift'),str(root/'Tests/WindowDiagnostics/main.swift'),'-o',str(output)],check=True)
 subprocess.run([str(output)],check=True)
