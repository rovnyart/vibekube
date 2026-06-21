# Vibekube Release Checklist

Use this checklist before publishing a DMG outside the development machine.

Historical validation: Vibekube has been used daily on a separate work Mac since version 0.3.0, including real-cluster workflows. That closes the Phase 11 clean-machine validation milestone as of 2026-06-20. Keep the checklist below as a fresh per-release pass for each new DMG.

## Build

- [ ] Confirm `docs/PROGRESS.md` has no missing must-fix item for the release.
- [ ] Confirm `docs/PRIVACY.md` matches the current app behavior.
- [ ] Confirm automatic telemetry, crash reporting, update checks, and AI network requests remain absent unless a new privacy review has landed.
- [ ] Run the non-UI test suite:

  ```sh
  xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test -only-testing:vibekubeTests
  ```

- [ ] Build, sign, notarize, staple, and verify the current version:

  ```sh
  NOTARY_PROFILE=vibekube-notary scripts/release current
  ```

- [ ] Keep the generated DMG and checksum from `dist/`.

## Clean-Machine Install

- [ ] Install the DMG on a Mac that is not the development machine.
- [ ] Confirm Gatekeeper opens the app without extra override steps.
- [ ] Confirm `About Vibekube` shows the expected version and build.
- [ ] Confirm the app starts with diagnostics file logging disabled.
- [ ] Enable diagnostics file logging, open the log folder from Settings, and confirm files go to `~/Library/Logs/Vibekube`.
- [ ] Disable diagnostics file logging again unless needed for validation.

## Demo Cluster Smoke Test

- [ ] Start the demo cluster from this repo.
- [ ] Connect to the demo context.
- [ ] Open Dashboard and confirm it loads without navigation lag.
- [ ] Open Pods and confirm the list is responsive.
- [ ] Confirm the Pods header shows watch status as `Live`.
- [ ] Open a Pod detail tab and confirm Overview, YAML, Metadata, Conditions, Env, Events, and Logs work.
- [ ] Confirm regular ConfigMap-backed env values are visible.
- [ ] Confirm Secret-backed env values are masked until individually revealed.
- [ ] Open Logs and test tail/since controls, live smart-follow/jump-to-latest, timestamps, JSONL formatting, search, grep, save displayed, download all, and previous logs.
- [ ] Switch namespaces using search/filter in the namespace picker.

## Real Cluster Smoke Test

- [ ] Log in to the corporate auth provider outside Vibekube, if required by the kubeconfig exec plugin.
- [ ] Connect to at least one real exec-auth cluster.
- [ ] Connect to at least one large namespace-heavy cluster.
- [ ] Confirm namespace search is usable with hundreds of namespaces.
- [ ] Open Pods in all-namespaces scope and confirm paginated loading shows progress and can be cancelled.
- [ ] Open a real workload Pod detail and confirm Env rendering is complete enough to debug.
- [ ] Confirm Secret-backed env values remain masked by default.
- [ ] Open Logs for a real workload and confirm copy/select/search/live smart-follow/JSONL behavior.
- [ ] Export diagnostics only if needed, then inspect the export for accidental secrets before sharing.

## Distribution Notes

- [ ] Publish the DMG and `.sha256` together.
- [ ] Include the supported macOS version, release version, and notarization status.
- [ ] Link to `docs/PRIVACY.md` or include its contents in release notes.
