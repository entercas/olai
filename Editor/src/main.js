import './editor.css'

import { Editor, InputRule } from '@tiptap/core'
import { Plugin } from '@tiptap/pm/state'
import { Decoration, DecorationSet } from '@tiptap/pm/view'
import { Transformer } from 'markmap-lib'
import { Markmap } from 'markmap-view'
import StarterKit from '@tiptap/starter-kit'
import Highlight from '@tiptap/extension-highlight'
import Image from '@tiptap/extension-image'
import Link from '@tiptap/extension-link'
import Placeholder from '@tiptap/extension-placeholder'
import TaskItem from '@tiptap/extension-task-item'
import TaskList from '@tiptap/extension-task-list'
import Underline from '@tiptap/extension-underline'

const EMPTY_DOC = { type: 'doc', content: [{ type: 'paragraph' }] }

// Documents store attachment://<uuid>, which is what the Markdown mirror will export.
// The web view is served from olai://editor, and only a same-origin URL will load, so
// the two are mapped as the image is rendered and parsed back.
const STORED_PREFIX = 'attachment://'
const SERVED_PREFIX = 'olai://editor/attachment/'

const servedSource = (src) =>
  typeof src === 'string' && src.startsWith(STORED_PREFIX)
    ? SERVED_PREFIX + src.slice(STORED_PREFIX.length)
    : src

const storedSource = (src) =>
  typeof src === 'string' && src.startsWith(SERVED_PREFIX)
    ? STORED_PREFIX + src.slice(SERVED_PREFIX.length)
    : src

const AttachmentImage = Image.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      src: {
        default: null,
        parseHTML: (element) => storedSource(element.getAttribute('src')),
        renderHTML: (attributes) => ({ src: servedSource(attributes.src) }),
      },
    }
  },
})

/** Posts a message to Swift. Silently does nothing in a plain browser, so the editor
 *  can still be opened with `npm run dev` while working on it. */
function post(name, payload = {}) {
  window.webkit?.messageHandlers?.bridge?.postMessage({ name, payload })
}

function debounce(fn, ms) {
  let timer = null
  const wrapped = (...args) => {
    clearTimeout(timer)
    timer = setTimeout(() => {
      timer = null
      fn(...args)
    }, ms)
  }
  wrapped.flush = (...args) => {
    if (timer === null) return
    clearTimeout(timer)
    timer = null
    fn(...args)
  }
  return wrapped
}

/** `[] ` and `[x] ` start a checklist. TaskList ships a wrapping rule for this, but a
 *  wrapping rule cannot apply inside an existing list item, which is exactly where
 *  someone turning a bullet into a checkbox types it. This rule is tried after the
 *  built-in one and converts the list the caret is already in. */
const CheckboxInputRule = TaskList.extend({
  addInputRules() {
    return [
      ...(this.parent?.() ?? []),
      new InputRule({
        find: /^\s*\[([ |xX])?\]\s$/,
        handler: ({ range, match, chain }) => {
          chain()
            .deleteRange(range)
            .toggleTaskList()
            .updateAttributes('taskItem', { checked: /[xX]/.test(match[1] ?? '') })
            .run()
        },
      }),
    ]
  },
})

/** Task items carry the identifier of the reminder they were scheduled as, plus a
 *  human-readable due date that the stylesheet renders as a chip. */
const ScheduledTaskItem = TaskItem.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      reminderID: {
        default: null,
        parseHTML: (el) => el.getAttribute('data-reminder-id'),
        renderHTML: (attrs) =>
          attrs.reminderID ? { 'data-reminder-id': attrs.reminderID } : {},
      },
      due: {
        default: null,
        parseHTML: (el) => el.getAttribute('data-due'),
        renderHTML: (attrs) => (attrs.due ? { 'data-due': attrs.due } : {}),
      },
    }
  },

  /** Shows when a scheduled task is due, just after its text.
   *
   *  TaskItem draws itself with a node view that builds its own DOM, so the attribute
   *  above never reaches the screen -- it only covers serialisation. A widget
   *  decoration puts a real element inline at the end of the task's first paragraph,
   *  which also keeps the chip next to the words rather than out at the margin. */
  addProseMirrorPlugins() {
    return [
      ...(this.parent?.() ?? []),
      new Plugin({
        props: {
          decorations: (state) => {
            const decorations = []

            state.doc.descendants((node, pos) => {
              if (node.type.name !== 'taskItem' || !node.attrs.due) return
              const paragraph = node.firstChild
              if (!paragraph) return

              const endOfText = pos + paragraph.nodeSize
              decorations.push(
                Decoration.widget(
                  endOfText,
                  () => {
                    const chip = document.createElement('span')
                    chip.className = 'due-chip'
                    chip.textContent = node.attrs.due
                    chip.contentEditable = 'false'
                    return chip
                  },
                  { side: 1 },
                ),
              )
            })

            return DecorationSet.create(state.doc, decorations)
          },
        },
      }),
    ]
  },
})

const editor = new Editor({
  element: document.querySelector('#editor'),
  extensions: [
    StarterKit.configure({ heading: { levels: [1, 2, 3] } }),
    Underline,
    Highlight,
    Link.configure({ openOnClick: false, autolink: true }),
    AttachmentImage.configure({ inline: false, allowBase64: false }),
    CheckboxInputRule,
    ScheduledTaskItem.configure({ nested: true }),
    Placeholder.configure({ placeholder: 'Start writing…' }),
  ],
  content: EMPTY_DOC,
  autofocus: false,
  onUpdate: () => {
    sendDocument()
    sendState()
  },
  onSelectionUpdate: sendState,
  onCreate: sendState,
})

// Saves are debounced 500 ms after the last change, as the spec describes.
const sendDocument = debounce(() => {
  post('documentChanged', { json: editor.getJSON(), plainText: editor.getText() })
}, 500)

/** What the SwiftUI toolbar needs to draw itself: which marks and blocks are active,
 *  and whether the caret sits in a task item that could be scheduled. */
function sendState() {
  const task = editor.isActive('taskItem')
    ? {
        active: true,
        text: taskItemText(),
        reminderID: editor.getAttributes('taskItem').reminderID ?? null,
        due: editor.getAttributes('taskItem').due ?? null,
      }
    : { active: false, text: '', reminderID: null, due: null }

  post('stateChanged', {
    bold: editor.isActive('bold'),
    italic: editor.isActive('italic'),
    underline: editor.isActive('underline'),
    strike: editor.isActive('strike'),
    highlight: editor.isActive('highlight'),
    code: editor.isActive('code'),
    h1: editor.isActive('heading', { level: 1 }),
    h2: editor.isActive('heading', { level: 2 }),
    h3: editor.isActive('heading', { level: 3 }),
    bulletList: editor.isActive('bulletList'),
    orderedList: editor.isActive('orderedList'),
    taskList: editor.isActive('taskList'),
    blockquote: editor.isActive('blockquote'),
    canUndo: editor.can().undo(),
    canRedo: editor.can().redo(),
    mindMap: mindMapVisible,
    task,
  })
}

/** The text of the task item holding the caret, used to name a reminder. */
function taskItemText() {
  const { $from } = editor.state.selection
  for (let depth = $from.depth; depth > 0; depth -= 1) {
    const node = $from.node(depth)
    if (node.type.name === 'taskItem') return node.textContent.trim()
  }
  return ''
}

/** Indent and outdent work on whichever kind of list item we are inside. */
function shiftListItem(direction) {
  const command = direction === 'in' ? 'sinkListItem' : 'liftListItem'
  const type = editor.isActive('taskItem') ? 'taskItem' : 'listItem'
  return editor.chain().focus()[command](type).run()
}

const COMMANDS = {
  bold: () => editor.chain().focus().toggleBold().run(),
  italic: () => editor.chain().focus().toggleItalic().run(),
  underline: () => editor.chain().focus().toggleUnderline().run(),
  strike: () => editor.chain().focus().toggleStrike().run(),
  highlight: () => editor.chain().focus().toggleHighlight().run(),
  code: () => editor.chain().focus().toggleCode().run(),
  paragraph: () => editor.chain().focus().setParagraph().run(),
  h1: () => editor.chain().focus().toggleHeading({ level: 1 }).run(),
  h2: () => editor.chain().focus().toggleHeading({ level: 2 }).run(),
  h3: () => editor.chain().focus().toggleHeading({ level: 3 }).run(),
  bulletList: () => editor.chain().focus().toggleBulletList().run(),
  orderedList: () => editor.chain().focus().toggleOrderedList().run(),
  taskList: () => editor.chain().focus().toggleTaskList().run(),
  blockquote: () => editor.chain().focus().toggleBlockquote().run(),
  codeBlock: () => editor.chain().focus().toggleCodeBlock().run(),
  horizontalRule: () => editor.chain().focus().setHorizontalRule().run(),
  indent: () => shiftListItem('in'),
  outdent: () => shiftListItem('out'),
  undo: () => editor.chain().focus().undo().run(),
  redo: () => editor.chain().focus().redo().run(),
  focus: () => editor.chain().focus().run(),
  flush: () => sendDocument.flush(),
  toggleMindMap: () => setMindMap(!mindMapVisible),
}

// MARK: Mind map
//
// A read-only view of the page's outline -- headings and the bullets under them --
// rendered with markmap in this same web view. No freeform canvas in v1.

const mindMapHost = document.createElement('div')
mindMapHost.id = 'mindmap'
mindMapHost.hidden = true
mindMapHost.innerHTML = '<svg></svg>'
document.body.appendChild(mindMapHost)

const transformer = new Transformer()
let markmap = null
let mindMapVisible = false

function textOf(node) {
  if (node.text) return node.text
  return (node.content ?? []).map(textOf).join('')
}

const isList = (type) => ['bulletList', 'orderedList', 'taskList'].includes(type)

/** The outline as Markdown: headings, and the bullets nested under them. */
function outlineMarkdown() {
  const lines = []

  const walkList = (list, depth) => {
    for (const item of list.content ?? []) {
      const paragraph = (item.content ?? []).find((child) => child.type === 'paragraph')
      const text = paragraph ? textOf(paragraph).trim() : ''
      if (text) lines.push(`${'  '.repeat(depth)}- ${text}`)

      for (const child of item.content ?? []) {
        if (isList(child.type)) walkList(child, depth + (text ? 1 : 0))
      }
    }
  }

  for (const node of editor.getJSON().content ?? []) {
    if (node.type === 'heading') {
      const text = textOf(node).trim()
      if (text) lines.push(`${'#'.repeat(node.attrs?.level ?? 1)} ${text}`)
    } else if (isList(node.type)) {
      walkList(node, 0)
    }
  }

  return lines.join('\n')
}

function renderMindMap() {
  const outline = outlineMarkdown()
  const svg = mindMapHost.querySelector('svg')

  if (!outline.trim()) {
    svg.innerHTML =
      '<text x="24" y="40" fill="currentColor" font-size="14">' +
      'Nothing to map yet — add a heading or a bullet.</text>'
    return
  }

  const { root } = transformer.transform(outline)
  if (!markmap) {
    markmap = Markmap.create(svg, { autoFit: true, duration: 200 }, root)
  } else {
    markmap.setData(root)
    markmap.fit()
  }
}

function setMindMap(visible) {
  mindMapVisible = visible
  mindMapHost.hidden = !visible
  document.querySelector('#editor').hidden = visible
  if (visible) renderMindMap()
  sendState()
}

// MARK: Dictation
//
// Speech recognition streams a revisable guess at the whole utterance, not a stream of
// new words: "the legacy" becomes "the latency" a moment later. So the text is held as
// a replaceable range and rewritten in place; appending each result would repeat the
// sentence every time the recogniser changed its mind.

let dictation = null // { from, to, text }

/** Whether `next` is a revision of `previous` rather than something new.
 *
 *  A revision refines the end of what was said -- "the legacy" becomes "the latency" --
 *  and keeps the beginning. A fresh utterance shares nothing. Without this, a second
 *  sentence spoken after a pause overwrote the first, because the recogniser starts its
 *  transcript over and the range still covered the earlier text. */
function continuesUtterance(previous, next) {
  if (!previous) return true

  const a = previous.trim().toLowerCase()
  const b = next.trim().toLowerCase()
  if (!a || !b) return true

  const shared = Math.min(8, a.length, b.length)
  return a.slice(0, shared) === b.slice(0, shared)
}

/** Drops the range if the text there is no longer ours -- the caret moved, or the
 *  document was edited while dictating. */
function dictationRangeIsIntact() {
  if (!dictation) return false
  const { doc } = editor.state
  if (dictation.to > doc.content.size) return false
  return doc.textBetween(dictation.from, dictation.to, '', '') === dictation.text
}

function replaceDictation(spoken) {
  if (!dictationRangeIsIntact()) dictation = null
  if (dictation && !continuesUtterance(dictation.spoken, spoken)) dictation = null

  if (!dictation) {
    // Focus first: the caret has to exist before its position means anything.
    editor.chain().focus().run()
    const from = editor.state.selection.to
    // A block boundary counts as whitespace, so a new paragraph needs no space.
    const before = editor.state.doc.textBetween(Math.max(from - 1, 0), from, ' ', ' ')
    dictation = { from, to: from, text: '', spoken: '', separator: before.trim() ? ' ' : '' }
  }

  const text = dictation.separator + spoken
  editor
    .chain()
    .insertContentAt({ from: dictation.from, to: dictation.to }, text)
    .run()

  dictation = { ...dictation, to: dictation.from + text.length, text, spoken }
}

/** Everything Swift can call. */
window.olai = {
  setDocument({ json, readOnly }) {
    editor.setEditable(!readOnly)
    editor.commands.setContent(json ?? EMPTY_DOC, false)
    if (mindMapVisible) renderMindMap()
    sendState()
  },

  insertText({ text }) {
    editor.chain().focus().insertContent(text).run()
  },

  /** Images live in the store, not the document: the src is resolved by the
   *  attachment:// scheme handler. */
  insertImage({ id, alt }) {
    editor.chain().focus().setImage({ src: `attachment://${id}`, alt: alt ?? '' }).run()
  },

  applyTheme({ dark }) {
    document.body.classList.toggle('dark', Boolean(dark))
  },

  command({ name, payload }) {
    const run = COMMANDS[name]
    if (run) run(payload)
    sendState()
  },

  /** Rewrites what is being dictated, in place. */
  setDictationText({ text }) {
    // No sendState here: the edit itself fires onUpdate, which reports state. Posting
    // twice per partial result only adds work between speaking and seeing the words.
    replaceDictation(text ?? '')
  },

  /** Ends the utterance: the next one starts its own range. */
  endDictation() {
    dictation = null
  },

  /** Records that this task item was scheduled, so it can be opened or updated later. */
  setTaskReminder({ reminderID, due }) {
    editor.chain().focus().updateAttributes('taskItem', {
      reminderID: reminderID ?? null,
      due: due ?? null,
    }).run()
    sendState()
  },
}

// Pasted and dropped images are handed to Swift, which stores the bytes and calls
// back with an attachment id. The document never carries base64 or a blob URL.
function sendImageFile(file) {
  const reader = new FileReader()
  reader.onload = () => {
    const result = String(reader.result)
    const base64 = result.slice(result.indexOf(',') + 1)
    post('requestImagePaste', { base64, mime: file.type, name: file.name || 'pasted' })
  }
  reader.readAsDataURL(file)
}

/** Clipboard images arrive as `files` from some sources and as `items` from others --
 *  a screenshot pasted on macOS is an item, not a file. Both must be read here,
 *  synchronously, while the event is still live. */
function imageFilesFrom(dataTransfer) {
  if (!dataTransfer) return []

  const files = Array.from(dataTransfer.files ?? []).filter((f) => f.type.startsWith('image/'))
  if (files.length > 0) return files

  return Array.from(dataTransfer.items ?? [])
    .filter((item) => item.kind === 'file' && item.type.startsWith('image/'))
    .map((item) => item.getAsFile())
    .filter(Boolean)
}

/** True when the clipboard holds an image but no file to read it from -- a screenshot,
 *  or anything else copied as raw image data. The page cannot reach those bytes, so
 *  Swift reads the pasteboard instead. Pastes carrying real text are left alone. */
function isUnreadableImage(transfer) {
  if (!transfer) return false

  const types = Array.from(transfer.types ?? [])
  const looksLikeImage =
    types.some((type) => type.startsWith('image/')) ||
    (transfer.getData('text/html') ?? '').includes('webkit-fake-url')

  return looksLikeImage && (transfer.getData('text/plain') ?? '').trim() === ''
}

/** Takes an image out of a paste or drop before ProseMirror inserts it itself, which
 *  it would do with a URL that resolves to nothing once the page reloads. */
function interceptImages(transfer) {
  const images = imageFilesFrom(transfer)
  if (images.length > 0) {
    images.forEach(sendImageFile)
    return true
  }

  if (isUnreadableImage(transfer)) {
    post('requestPasteboardImage')
    return true
  }

  return false
}

editor.setOptions({
  editorProps: {
    handlePaste: (_view, event) => interceptImages(event.clipboardData),
    handleDrop: (_view, event) => interceptImages(event.dataTransfer),
  },
})

document.addEventListener('dragover', (event) => {
  if (imageFilesFrom(event.dataTransfer).length > 0) event.preventDefault()
})

// A page can be closed mid-edit; do not sit on a pending save.
window.addEventListener('blur', () => sendDocument.flush())
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'hidden') sendDocument.flush()
})

post('ready')
