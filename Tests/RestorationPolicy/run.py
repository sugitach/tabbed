#!/usr/bin/env python3
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='tabbed-restoration-') as d:
 subprocess.run(['/usr/bin/xcrun','swiftc','-swift-version','5','-sdk','/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk','-module-cache-path',d+'/cache',str(root/'Sources/Group/WindowRestoration.swift'),str(root/'Tests/RestorationPolicy/main.swift'),'-o',d+'/tests'],check=True)
 subprocess.run([d+'/tests'],check=True)
