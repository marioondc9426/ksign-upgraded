
<img src="https://github.com/user-attachments/assets/986892f9-c32f-448d-a24e-ba8659203fbf" height="200">

# Ksign+ (upgraded fork)
[![Beta Build](https://img.shields.io/github/actions/workflow/status/marioondc9426/ksign-upgraded/beta.yml?style=for-the-badge&label=beta%20build)](https://github.com/marioondc9426/ksign-upgraded/actions/workflows/beta.yml)
[![Upstream](https://img.shields.io/badge/upstream-Nyasami%2FKsign-3c94fc?style=for-the-badge)](https://github.com/Nyasami/Ksign)

Fork of [Ksign](https://github.com/Nyasami/Ksign), the Esign-like codesigning app built on Feather, with extra features on top.

## What's new in this fork
- **Update badge in the App Store tab**: if an app in your library (imported or signed) has the same bundle identifier as an app in a source and the source has a newer version, the button shows **Update** instead of **Get**. Matching is by bundle identifier only (like `com.google.youtube`), never by name, and versions are compared numerically (1.10 is newer than 1.9)
- **Updates tab**: every app in your library with a newer version in your sources, with Update and Update All. Also reachable from the App Store tab (badge with the count)
- **Sign updates automatically** (setting): updating an app you signed before signs the new version again with the same options and certificate
- **Update notifications** (setting): checks your sources when the app opens and in the background, and notifies about new versions
- **Auto source with every version**: the *Update Source* workflow archives each build as its own release and keeps a source with all of them. Add `https://raw.githubusercontent.com/marioondc9426/ksign-upgraded/source/source.json` in Ksign to get updates of the app itself (and any ipa you put in a release)
- **New update alert**: every time the app opens and something has a new version, an alert offers to update it. With *Sign updates automatically* (on by default) the update is signed again with the old options and certificate and replaces the old one
- **Home tab**: a hello, Quick Sign & Install for your downloaded apps and a button to import an IPA into the library
- **Signing presets**: save options + certificate as a preset (from the signing screen or Settings > Signing Presets), apply it with one tap, and add rules that change name, identifier, certificate or tweaks for specific apps (`com.google.*` style wildcards)
- **Quick Sign & Install**: in the library, tap an app and pick Quick Sign & Install to sign it with your default preset and open the install sheet right away
- **TrollStore install**: new install method that sends the signed IPA to TrollStore (only offered where the CoreTrust bug exists: iOS 14.0 to 16.6.1 and 17.0). Settings > Installation also shows if TrollStore and AppSync Unified are found
- **AppSync**: on a jailbroken device with AppSync Unified turn on *Sign without certificate* (Settings > Installation) and every signing, bulk signing, update and re-sign uses a fake (ad-hoc) signature, no certificate needed
- **Presets in Bulk Signing**: apply a preset, with its per-app rules, to every selected app at once
- **Certificate alerts**: warns 3 days before a certificate ends, and when you add a certificate that lasts longer than the one your signed apps use
- **Bulk Re-sign** (Settings): sign your signed apps again with another certificate in one go, older certificates are pre-selected
- **Open in Ksign**: open an IPA from Safari, Files or any share sheet and Ksign goes straight to the signing screen
- **Presets with description and tweaks**: Add preset opens a popup with name, description and the tweaks it injects. Presets (with their tweak files) are part of Backup & Restore
- **Signing History**: everything you signed, with certificate, preset and result, and a Redo swipe
- **Storage**: size of every app in the library and a one-tap delete of the originals that already have a signed copy
- **Certificate card on Home**: days left of the certificate that ends first, tap to sign everything again
- **TrollStore and AppSync certificates**: on a jailbroken device two extra entries show up in the certificate list, TrollStore (999 days) and AppSync (until reboot). They hold no files: signing with them is ad-hoc, and the TrollStore one installs through TrollStore
- **Jailbreak protection**: Ksign detects a jailbroken device and, with the setting on (default), never uses your certificates there: everything is signed ad-hoc and backups are disabled, since any tweak or root process could read the certificate and its password
- **Backup & Restore**: sources and your own certificates in one zip (the certificates shipped inside the app are not exported)
- **Bulk signing with tweaks**: add tweaks to all selected apps at once, or per app
- **Server Diagnostics**: method, address, certificate expiry and a test of the certificate pack download
- **Multi Sign**: pick several apps and sign them one after another with a progress view
- **Faster sources**: repositories download concurrently and the app list fills in as each one arrives
- **Source cache**: the last copy of every source is kept on disk, so the App Store (and the update badges) show up at once when the app opens while the new download runs
- **App Store info**: source description plus the iTunes description and screenshots in the library info page
- **Unlock button**: shortcut to the ARM Converter store page from Library and App Store
- **Better local install**: more reliable Fully Local / Semi Local install server (certificate expiry fallback, Wi-Fi address detection, tap-to-install page)
- **Share Logs**: export diagnostics from the install screen to help debug problems

## Building
Pushes to `main` run the **Beta Build** workflow (macOS runner) and publish an unsigned `KsignPlus.ipa` to the Beta release of this fork. You can also start it by hand from the Actions tab (Run workflow) without pushing anything.

## Original project
Ksign was built because Esign reached end of service, using Feather as the base, and for Khoindvn to share certificates. Upstream issues and Discord: [Issue](https://github.com/Nyasami/Ksign-public/issues), [Discord](https://discord.gg/sfbZfQzVdQ).

## Special thanks
- Feather by [claration](https://github.com/claration/Feather)
- Ksign by [Nyasami](https://github.com/Nyasami/Ksign)
- Product manager Khoindvn
- And you! for using the app ❤️

## Disclaimer
This is an unofficial fork. Releases of this fork are distributed from this repository only. Avoid sites that host the app, they are often malicious.
