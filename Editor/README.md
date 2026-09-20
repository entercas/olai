# Olai web editor

TipTap in a WKWebView, per the spec's non-negotiable decision 2. Vite inlines the whole
thing into one file, which is committed at `Olai/Resources/editor.html` so the app
builds without Node.

```bash
cd Editor
npm install
npm run build     # builds and copies the result into Olai/Resources/editor.html
```

Commit `Olai/Resources/editor.html` with any change to this directory.

## Bridge

Handler name `bridge`, JSON messages, as in the spec. Two additions the SwiftUI toolbar
needs: `command` going out, and `stateChanged` coming back.

| Direction | Message | Purpose |
| --- | --- | --- |
| Swift → JS | `setDocument({json, readOnly})` | Load a page |
| Swift → JS | `insertText({text})` | Dictation and slash commands |
| Swift → JS | `insertImage({id})` | Reference a stored attachment |
| Swift → JS | `applyTheme({dark})` | Follow the system appearance |
| Swift → JS | `command({name})` | Toolbar actions |
| Swift → JS | `setTaskReminder({reminderID, due})` | Record a scheduled task on the block |
| JS → Swift | `ready` | The editor is loaded |
| JS → Swift | `documentChanged({json, plainText})` | Debounced 500 ms after the last change |
| JS → Swift | `stateChanged({...})` | Active marks and blocks, for the toolbar |
| JS → Swift | `requestImagePaste({base64, mime, name})` | A pasted or dropped image |

## Images

Documents store `attachment://<uuid>`, which is what the Markdown mirror will export.
The page is served from `olai://editor/index.html` and images from
`olai://editor/attachment/<uuid>`: a `file://` origin is not permitted to load a custom
scheme, so both have to sit on one origin. The image extension maps between the stored
and served forms as it renders and parses.
