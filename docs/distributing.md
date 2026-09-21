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

1. **A Developer ID Application certificate.** Xcode ▸ Settings ▸ Accounts ▸ your
   account ▸ Manage Certificates ▸ **+** ▸ Developer ID Application. Apple allows a
   small number of these per account, and they are what your name is attached to on
   every copy you hand out — keep the private key backed up.

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
