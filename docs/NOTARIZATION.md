# Notarization

`./build.sh` ad-hoc signs NetworkMon for local use (`codesign --sign -`).

To distribute outside your Mac:

1. Join the Apple Developer Program and install a **Developer ID Application** certificate.
2. Build: `./build.sh`
3. Create a notarytool keychain profile (once):

```bash
xcrun notarytool store-credentials "NetworkMon-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

4. Notarize:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./notarize.sh
```

5. Ship the stapled `NetworkMon.app`.
