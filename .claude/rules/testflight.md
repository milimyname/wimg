# TestFlight — wimg iOS

## Prerequisites

- Apple Developer account (paid, $99/year)
- Xcode with signing configured (Team: W5N395VNYH)
- App registered in App Store Connect (Bundle ID: `com.wimg.app`)

## Upload a New Build

1. Bump version in `project.yml`:
   - `MARKETING_VERSION` for new releases (e.g. `0.6.15` → `0.7.0`)
   - `CURRENT_PROJECT_VERSION` must increment for each upload with the same marketing version
2. Regenerate the Xcode project:
   ```
   cd wimg-ios && xcodegen
   ```
3. In Xcode:
   - **Shift+Cmd+K** — Clean Build Folder
   - **Product → Archive**
   - **Distribute App → TestFlight Internal Testing**
4. Wait ~5-15 min for Apple to process the build
5. In App Store Connect → TestFlight → your test group → Builds → **+** → select the new build

## First-Time Setup (already done)

1. Register Bundle ID at developer.apple.com/account/resources/identifiers
2. Create app in App Store Connect (appstoreconnect.apple.com)
3. Create internal test group (TestFlight → Internal Testing → +)
4. Add testers by Apple ID email
5. Testers install the TestFlight app on their iPhone and accept the invite

## Encryption Compliance

Select "None of the algorithms mentioned above" — the app uses only standard
Apple-provided encryption (HTTPS/TLS).

## Notes

- Internal testing: up to 100 testers, no Apple review, builds available immediately after processing
- External testing: up to 10,000 testers, first build requires beta review (~24h)
- `embed: false` for libwimg.xcframework — it's a static library (.a), linked at compile time
- App icon must be 1024x1024 PNG with no alpha channel
- iPad builds require all 4 orientation entries in Info.plist
- `release.sh` bumps `MARKETING_VERSION` in `project.yml` automatically
- Build number (`CURRENT_PROJECT_VERSION`) must be bumped manually for each TestFlight upload
