# Roadmap

Where Nida is going next. Versions follow semantic versioning: minor versions add features, patch versions fix
bugs. Order and scope can change; each item lands with its README and documentation updates.

Two rules apply to everything below:

- **Small footprint.** Nida stays at about 17 MB memory and close to 0% CPU when idle. New background work
  (update checks, licence checks) runs at most a few times a day and never on a per-second timer.
- **Private by default.** Today Nida only talks to the network for Apple's location lookup and city search.
  Anything new that contacts a server is explained in the app, can be turned off, and sends no location or
  personal data.

## Current: 1.3.1

Live countdown, minimal CPU and memory, README screenshots, tag-triggered release workflow (not yet run on
GitHub).

## 1.3.1: first real release run

- Push `v1.3.0` and confirm `.github/workflows/release.yml` builds, verifies and publishes the DMG on GitHub's
  runner. Fix whatever the first run exposes (runner Xcode version, `hdiutil`, Finder layout step).
- Add a `CHANGELOG.md` and use it for release notes.

## 1.4.0: dependency watching and CI

- **Dependabot** (`.github/dependabot.yml`):
  - `swift` ecosystem: weekly checks for `adhan-swift`, the prayer-time library everything depends on.
  - `github-actions` ecosystem: keeps `actions/checkout`, `actions/cache`, `actions/upload-artifact` current.
  - Grouped minor/patch updates; major versions in their own pull request.
- **CI on every push and pull request** (`.github/workflows/ci.yml`), so Dependabot's pull requests are tested
  before merging: debug and release builds, both architectures.
- **Prayer-time regression tests**: a test target with known-good times (the Aladhan cross-checks for Makkah,
  Paris, London, New York, Cairo, Karachi, Dakar, Istanbul, Kuala Lumpur, plus a polar case) so a library update
  that shifts any time by more than a minute fails CI instead of shipping.
- GitHub security alerts and secret scanning enabled on the repository.

## 1.5.0: automatic updates through Warden

Nida checks for new versions itself and installs them in one click, using Warden as the release server
instead of a third-party update framework.

- Publish each Nida release to a **Nida app in Warden** (Warden's GitHub publishing can pick it up from the
  release workflow), on **stable** and **beta** channels.
- Nida calls the Warden check URL about once a day and on wake (never more often), reading `update` for the
  latest version on its channel. It sends only its version and channel.
- When an update exists: a quiet badge in the popover and a notification, with **Update now** / **Later** /
  **Skip this version**. Settings › General: *Check for updates automatically*, *Install updates automatically*,
  channel picker.
- Download over HTTPS from Warden's signed download link, verify the SHA-256 and code signature (same Team ID
  as the running app) before installing. Then reuse the existing install/update path from `Installer.swift`:
  quit, replace, relaunch, settings kept.
- Fallback: if Warden can't be reached, nothing breaks; Nida keeps working and tries again later.
- Requires Developer ID signing to be meaningful (see 1.7.0); with ad-hoc builds, the update is offered but the
  signature check is limited to the checksum.

Open questions to settle before building: what Nida sends in place of `domain` (Warden checks are per site; a
Mac app needs a random per-install ID or a dedicated app check), and whether beta is opt-in only.

## 1.6.0: Warden licence support

Optional, for distributing Nida (or a branded build) to clients under a Warden licence.

- Settings › About: enter a licence key (`WRD-…`), show its status and the message Warden returns.
- Check every 12 hours like other Warden clients, with an offline grace period so an unreachable server never
  stops the adhan.
- Build-time switch: the public build stays free with no licence prompt; licensed builds turn it on.
- Decide first: does the free public build stay licence-free for good? (Recommended: yes.)

## 1.7.0: trusted distribution

- Developer ID signing and notarization in the release workflow (secrets are already documented in the README),
  so no "unidentified developer" warning on other Macs.
- Homebrew cask (`brew install --cask nida`).
- Real screenshots captured from the menu bar for the README.
- README available in French and Arabic.

## 1.8.0: multiple languages

Nida follows the Mac's language (System Settings › General › Language & Region), with a per-app override in
Settings › General.

- **First languages: French and Arabic.**
- **Then, by size of the Muslim population Nida serves:** Urdu, Indonesian, Turkish, Bengali, Malay, Persian,
  Spanish and German.
- **Right-to-left** layout for Arabic, Urdu and Persian: popover, settings, setup and the menu bar text, checked
  with the README screenshots rendered in each language (`--readme` gains a language option).
- **Everything translated**: menu bar text, popover, settings, setup, notifications, the "move" and
  "convention" prompts, voice titles, error messages, and the DMG window text.
- **Already localized by macOS** and kept that way: times, numbers (including Arabic-Indic digits) and Hijri
  month names follow the chosen language through the system formatters.
- **Prayer names**: the transliterated names (Fajr, Dhuhr…) stay as they are for languages written in Latin
  script. Other languages use their own script (الفجر, فجر, ফজর…).
- **How**: strings move to `Localizable.strings` files in `Resources/<lang>.lproj` with `defaultLocalization` in
  `Package.swift`. This works with the Command Line Tools alone; String Catalogs (`.xcstrings`) would need full
  Xcode to compile. A check in CI fails the build when a language is missing a string.
- Translations reviewed by native speakers before each language ships. Religious terms and convention names are
  reviewed carefully.

## Ideas, not scheduled

- Ramadan mode: suhoor and iftar countdowns, Imsak time.
- Islamic dates and events in the popover (Eid, Laylat al-Qadr, Ashura).
- A desktop / Notification Center widget.
- Mosque timetable import (iqamah times) as an alternative to calculated offsets.
- Shortcuts actions ("time until next prayer", "stop adhan").
