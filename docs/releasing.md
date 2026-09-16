# Releasing Glade

Glade uses the same distribution pattern as TMUX Manager: Developer ID signed and notarized DMGs in GitHub Releases, with Sparkle update signatures in an appcast served by GitHub Pages.

## Release configuration

| Setting | Value |
| --- | --- |
| Repository | `alxrod/glade` |
| Xcode project | `app/Glade/Glade.xcodeproj` |
| Scheme / configuration | `Glade` / `Release` |
| Distribution app | `Glade.app` |
| Distribution bundle ID | `net.alexbrodriguez.glade` |
| Minimum macOS | 14.0 |
| Appcast | `https://alxrod.github.io/glade/appcast.xml` |
| Pages source | `gh-pages`, repository root |
| Sparkle Keychain account | `Glade` |
| Existing notarization profile | `AC_PASSWORD` |

Set the signing team in the gitignored `app/Glade/Local.xcconfig`. The Sparkle private key is app-specific and stays in Keychain. Its encrypted backup lives in the owner's private agent-config repository; never commit the private key or credentials here. The public key is committed in `Info.plist`.

## Channels and versions

Use the `push-update` skill with an explicit channel, for example “ship a Glade beta.”

| Channel | Marketing version example | Appcast channel | GitHub release |
| --- | --- | --- | --- |
| Release | `1.5.0` | Omit `sparkle:channel` | Normal release |
| Beta | `1.5.0-beta.1` | `beta` | Prerelease |
| Alpha | `1.5.0-alpha.1` | `alpha` | Prerelease |

Examples are illustrative, not published builds. Increment `CURRENT_PROJECT_VERSION` beyond every previously published build across **all** channels. Set `MARKETING_VERSION` in both configurations. `Info.plist` expands these into the bundle versions.

Release subscribers see untagged items. Beta subscribers see beta and release items; alpha subscribers see every channel. Moving to a more stable channel waits for a newer eligible build instead of installing an older one. Preserve prior appcast items so each audience can still find its newest eligible update.

## Publish sequence

1. Run `swift test`. Archive the **Release** configuration for a generic macOS destination, with both Apple silicon and Intel architectures. Export the archive using the `developer-id` method. Debug builds have a different name and bundle ID and must never be distributed through the release feed.
2. Verify the exported app's bundle ID, versions, sandbox entitlements, hardened runtime, and Developer ID signatures. Verify the nested Sparkle framework, installer, downloader, updater app, and autoupdate helper. Archive/export handles signing those nested components; do not use `codesign --deep` to sign them.
3. Zip the exported app with `ditto -c -k --keepParent`, submit it with `xcrun notarytool submit ... --keychain-profile AC_PASSWORD --wait`, then staple and validate the accepted ticket on the app. Create a DMG containing that notarized `Glade.app` and an Applications shortcut. Sign the DMG with Developer ID, submit it separately, staple its accepted ticket, and validate it. Complete all stapling before producing the Sparkle signature.
4. Sign the final DMG with Sparkle's `sign_update --account Glade <path-to-dmg>`. Keep its exact byte length and EdDSA signature for the appcast enclosure.
5. Publish the DMG and release notes to `alxrod/glade` GitHub Releases. Mark alpha and beta builds as prereleases. The appcast enclosure must use the permanent GitHub release asset URL.
6. Add an item to `gh-pages/appcast.xml`, preserving older items. Include the marketing version, globally increasing build number, minimum macOS, publication date, download URL, byte length, and EdDSA signature. Include `sparkle:channel` only for beta or alpha builds. Push the feed after the release asset is available.
7. Fetch the hosted appcast and validate its XML, signature metadata, and download URL. Check for updates from an older installed copy on the intended channel to verify download, installation, relaunch, and version advancement.

The first stable release is Glade 1.0.0 (build 3). A real update install-and-relaunch test requires a subsequent newer signed build; checking the feed and validating a download alone do not cover that flow.
