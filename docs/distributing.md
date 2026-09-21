# Giving Olai to other people

You do not need the App Store, and nothing here goes through App Review. Direct
distribution with a **Developer ID** signature plus **notarisation** produces a `.dmg`
anyone can open.

## Notarisation is not App Review

Worth separating, because they are often confused:

| | App Review | Notarisation |
| --- | --- | --- |
| Who looks at it | a reviewer | an automated scan |
| Judges whether the app is a duplicate, useful, well designed | yes | no |
| Can reject you for being similar to other apps | yes | no |
| Typical wait | days | minutes |
| Needed to hand someone a `.dmg` | no | yes |

Notarisation checks for malware and for correct signing. It has no opinion about what
the app does or whether something like it already exists.

## Once, before the first release

1. **A Developer ID Application certificate.**

   In Xcode:

   - **Xcode ▸ Settings…** (⌘,) ▸ **Accounts**
   - Pick your Apple ID on the left. If it is not listed, **+** ▸ Apple ID and sign in —
     this is the developer account, and it is not the same as signing the Mac in to
     iCloud.
   - Select your team on the right, then **Manage Certificates…**
   - **+** at the bottom left ▸ **Developer ID Application**
   - It appears in the list after a few seconds. Close the sheet.

   Confirm it landed:

   ```bash
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```

   Two things worth knowing:

   - Apple allows only a handful of these per account, and only the Account Holder can
     create one. On an individual account that is you.
   - **Back up the private key.** Keychain Access ▸ My Certificates ▸ right-click the
     Developer ID certificate ▸ Export ▸ save as `.p12` with a password, somewhere safe.
     Lose it and you cannot sign updates as the same identity — anyone who already has
     the app then sees a different developer, and macOS treats it as a different app
     for permissions.

   If the **+** menu does not offer Developer ID Application, the account is signed in
   with a role that cannot create one, or the membership has lapsed. The portal route is
   the alternative: [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates)
   ▸ **+** ▸ Developer ID Application, which asks for a certificate signing request that
   you make in Keychain Access ▸ Certificate Assistant ▸ Request a Certificate From a
   Certificate Authority.

2. **Notarisation credentials in the keychain.** Create an app-specific password at
   [appleid.apple.com](https://appleid.apple.com) ▸ Sign-In and Security ▸ App-Specific
   Passwords, then:

   ```bash
   xcrun notarytool store-credentials olai \
     --apple-id you@example.com --team-id YQSS8GQ6Y4 --password <app-specific-password>
   ```

   Stored in your keychain, so the script never sees it again.

## Every release

```bash
scripts/release-mac.sh
```

It archives, exports with your Developer ID, submits to Apple, waits for the answer,
staples the ticket to the app so it opens without a network check, and builds
`build/release/Olai.dmg`.

The hardened runtime is on for Release builds, which notarisation requires. The app runs
under it unchanged — the web editor, the microphone and Reminders all work.

## Before you hand it to anyone

Two things about this app in particular:

- **Their notes sync into your CloudKit container.** Each person's data goes to their own
  private database, which nobody else can read — including you. But the container
  `iCloud.com.entercas.olai` is yours, so its quota and Apple's terms for it sit with
  your account. A handful of friends is nothing; a few thousand strangers is a service
  you are running.
- **They will see permission prompts** for Reminders, the microphone and speech
  recognition, the first time they use a scheduled task or dictation. Worth saying so up
  front, because unexplained prompts make people close an app.

If you would rather hand out something with no sync at all, build the local variant in
[install-second-mac.md](install-second-mac.md) and notarise that instead: it has no
iCloud entitlement, so nothing touches your container.

## What the recipient does

Open the `.dmg`, drag Olai to Applications, launch it. Because it is signed and stapled,
Gatekeeper opens it without a warning and without right-click-Open tricks.
