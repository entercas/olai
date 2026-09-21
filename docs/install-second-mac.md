# Installing Olai on a second Mac

Olai has no installer: it is source that Xcode builds. There are two ways to run it on
another machine, and the difference is whether that machine is signed in to the Apple ID
holding your notes.

## Which one you want

| | **Local build** | **Signed build** |
| --- | --- | --- |
| Apple ID in Xcode | not needed | your developer account |
| iCloud sign-in on the Mac | not needed | required |
| Notes sync with your other Macs | no | yes |
| Notarisation | no | no |
| Notes get there by | copying the Markdown mirror | iCloud |

Notarisation is not involved either way. It only matters for giving an app to *other*
people; building and running your own app on your own Mac never needs it. (It is also
automated and takes minutes — it is not an approval queue — but you do not need it here.)

## Local build: no Apple ID at all

Everything works except sync: the editor, templates, the Markdown mirror, reminders,
dictation. The store is local to that machine.

```bash
brew install xcodegen          # or: brew install --cask xcodegen
cd olai
xcodegen generate

xcodebuild -scheme Olai -destination 'platform=macOS' -derivedDataPath build/local \
  CODE_SIGN_ENTITLEMENTS=Olai/Olai-macOS-local.entitlements \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" \
  build

cp -R build/local/Build/Products/Debug/Olai.app /Applications/
```

`Olai-macOS-local.entitlements` is the same set of permissions without iCloud and without
push, so nothing needs a provisioning profile and the app signs locally. The app notices
it has no iCloud entitlement and opens a local store instead of asking CloudKit for one.

To move notes on and off that machine, use the Markdown mirror: point Settings at a
folder, and the pages are written there as files you can copy.

## Signed build: sync, with the Apple ID

This is the ordinary build. It needs your developer account signed in to Xcode, and the
Mac signed in to iCloud with the Apple ID holding the notes — in System Settings, not in
a browser. Signing in to iCloud.com in Chrome does not sync anything to a native app.

```bash
xcodegen generate
xcodebuild -scheme Olai -destination 'platform=macOS' -allowProvisioningUpdates build
```

On a work laptop, think about this one before doing it: it puts your personal iCloud
account on a machine your employer manages, which may be against their policy and is
worth checking first.

## Getting Xcode

Xcode is required either way; it is about 10 GB. From the Mac App Store, or from
[developer.apple.com/downloads](https://developer.apple.com/download/all/) — that page
asks for an Apple ID in the browser, which is only used to download and does not sign the
machine in to anything.

## Just the agent, no app

If all you want on that machine is to ask questions about notes written elsewhere, skip
the app entirely: copy the mirror folder and the 24 KB server bundle. See
[work-laptop.md](work-laptop.md).
