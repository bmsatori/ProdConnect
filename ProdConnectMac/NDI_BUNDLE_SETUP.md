Bundled NDI Setup For ProdConnectMac

ProdConnectMac now looks for bundled NDI libraries/frameworks before falling back to any system-installed runtime.

Supported bundled locations inside the app:

- `Contents/Frameworks/libndi.dylib`
- `Contents/Frameworks/NDIlib.framework/NDIlib`
- `Contents/Frameworks/NDI.framework/NDI`
- `Contents/Resources/NDI/libndi.dylib`
- `Contents/Resources/NDI/NDIlib.framework/NDIlib`
- `Contents/Resources/libndi.dylib`

Recommended approach:

1. Keep the official NDI macOS SDK binary at `ProdConnectMac/NDI/libndi.dylib`.
2. Keep the bundled license text at `ProdConnectMac/NDI/libndi_licenses.txt`.
3. Ensure the `Embed NDI Runtime` build phase remains on the `ProdConnectMac` target.
4. Rebuild ProdConnectMac.

Notes:

- `ProdConnectMac` now embeds `ProdConnectMac/NDI/libndi.dylib` into `Contents/Frameworks/libndi.dylib`.
- `ProdConnectMac/NDI/libndi_licenses.txt` is copied into app bundle resources for redistribution tracking.
- If the binary is removed from the target or bundle, ProdConnectMac falls back to preview/output-window mode only.
