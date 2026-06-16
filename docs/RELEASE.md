# Vibekube Release

This document describes how to build a signed DMG for direct macOS distribution.

## What The Script Does

`scripts/release`:

- bumps `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode project for `patch`, `minor`, `major`, or `set X.Y.Z`;
- runs the non-UI unit test target unless `--skip-tests` is passed;
- archives and exports the app with the Xcode `developer-id` distribution method;
- creates `dist/Vibekube-X.Y.Z.dmg`;
- signs and verifies the DMG;
- notarizes, staples, and Gatekeeper-assesses the DMG when `NOTARY_PROFILE` is configured;
- writes `dist/Vibekube-X.Y.Z.dmg.sha256`.

## Current Build

The project is currently set to `0.1.6` with build `7`.

```sh
NOTARY_PROFILE=vibekube-notary scripts/release current
```

For a local packaging dry run without notarization:

```sh
scripts/release current --skip-notarize
```

## Version Bumps

```sh
NOTARY_PROFILE=vibekube-notary scripts/release patch
NOTARY_PROFILE=vibekube-notary scripts/release minor
NOTARY_PROFILE=vibekube-notary scripts/release major
NOTARY_PROFILE=vibekube-notary scripts/release set 0.2.0
```

`patch`, `minor`, `major`, and `set` increment `CURRENT_PROJECT_VERSION` when the marketing version changes. `current` packages the version already in the project.

## Apple Setup

Direct online distribution requires Apple Developer ID signing and notarization.

1. Join the Apple Developer Program for the team configured in Xcode.
2. In Xcode, sign in with the Apple ID for that developer team.
3. Create/download a `Developer ID Application` certificate for the team.
4. Confirm the certificate is visible locally:

   ```sh
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```

5. Create a notarytool keychain profile. Use an app-specific password or App Store Connect API key.

   App-specific password example:

   ```sh
   xcrun notarytool store-credentials vibekube-notary \
     --apple-id "you@example.com" \
     --team-id "PTDKV576F4" \
     --password "xxxx-xxxx-xxxx-xxxx"
   ```

   API key example:

   ```sh
   xcrun notarytool store-credentials vibekube-notary \
     --key "/absolute/path/AuthKey_XXXXXXXXXX.p8" \
     --key-id "XXXXXXXXXX" \
     --issuer "00000000-0000-0000-0000-000000000000"
   ```

6. Run the release script with `NOTARY_PROFILE=vibekube-notary`.

The app target already has hardened runtime enabled, which Apple requires for notarization.

## Verification

The script runs:

```sh
codesign --verify --deep --strict --verbose=2 Vibekube.app
hdiutil verify Vibekube-X.Y.Z.dmg
codesign --verify --verbose=2 Vibekube-X.Y.Z.dmg
xcrun stapler validate Vibekube-X.Y.Z.dmg
spctl --assess --type open --verbose=4 Vibekube-X.Y.Z.dmg
```

The `stapler` and `spctl` checks only run when notarization is enabled.

## 0.1.x Release Checklist

Use [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) before publishing a DMG outside the development machine.

At minimum:

- Run `scripts/release current` with notarization enabled.
- Install the DMG on a non-development Mac.
- Confirm About Vibekube shows the expected version/build.
- Connect to the local demo cluster.
- Connect to at least one real exec-auth cluster.
- Open Pods, Logs, YAML, Events, and Env for a real workload.
- Verify regular env values are visible and Secret-backed env values stay masked until reveal.
- Confirm diagnostics logging is disabled by default and, when enabled, writes to `~/Library/Logs/Vibekube`.
- Confirm app errors are actionable enough to debug without Xcode.
