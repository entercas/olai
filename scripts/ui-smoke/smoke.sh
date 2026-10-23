#!/bin/bash
# End-to-end UI smoke test. Launches Olai in test mode -- an in-memory store of fixture
# notes and a preferences suite of its own, so nothing here can touch a real library or
# the Markdown mirror -- then drives it the way a person does and checks each result.
#
#   scripts/ui-smoke/smoke.sh [path/to/Olai.app] [output-dir]
#
# Run it against the notarised build before shipping, not only a Debug build: that is
# the thing people install. Needs Accessibility permission for the terminal running it.
#
# It runs beside a copy of Olai someone is using without touching it: every read, click
# and keystroke is held to the test's own process (OLAI_PID), and nothing here quits or
# activates Olai by name.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
app="${1:-$here/../../build/dev/Build/Products/Debug/Olai.app}"
out="${2:-$(mktemp -d)/olai-smoke}"
mkdir -p "$out"

driver="$out/drive"
swiftc -O "$here/Driver.swift" -o "$driver" 2>/dev/null || { echo "could not build the driver"; exit 1; }

prefs="$HOME/Library/Containers/com.entercas.olai/Data/Library/Preferences/com.entercas.olai.uitesting"
passed=0
failed=0
step=0

ax() {
    case "$1" in
        type) keys_type "$2" ;;
        key) keys_press "$2" "${3:-}" ;;
        *) "$driver" "$@" 2>/dev/null ;;
    esac
}

keys_type() {
    [ "$("$driver" frontmost 2>/dev/null)" = yes ] || { echo "REFUSED: Olai is not in front" >&2; return 4; }
    osascript -e "tell application \"System Events\" to keystroke \"$1\"" >/dev/null 2>&1
}

keys_press() {
    [ "$("$driver" frontmost 2>/dev/null)" = yes ] || { echo "REFUSED: Olai is not in front" >&2; return 4; }
    local using=""
    case "$2" in
        cmd) using=" using command down" ;;
        cmd,shift) using=" using {command down, shift down}" ;;
        cmd,opt) using=" using {command down, option down}" ;;
    esac
    osascript -e "tell application \"System Events\" to key code $1$using" >/dev/null 2>&1
}
count() { ax count "$1"; }
# The page's title field is the text field whose placeholder is "Untitled".
title() { ax value "AXTextField:Untitled" 0; }
settle() { sleep "${1:-1}"; }

shot() {
    local id
    id=$(ax windowid)
    [ -n "$id" ] && screencapture -x -o -l "$id" "$out/$(printf '%02d' "$step")-$1.png"
}

check() {
    # check "description" <actual> <expected>
    step=$((step + 1))
    if [ "$2" = "$3" ]; then
        printf '  PASS  %02d  %s\n' "$step" "$1"
        passed=$((passed + 1))
    else
        printf '  FAIL  %02d  %s   (got "%s", wanted "%s")\n' "$step" "$1" "$2" "$3"
        failed=$((failed + 1))
    fi
    shot "$(echo "$1" | tr -c 'a-zA-Z0-9' '-' | cut -c1-40)"
}

atLeast() { [ "${1:-0}" -ge "$2" ] 2>/dev/null && echo yes || echo no; }

menu_item() {
    # menu_item <menu> <item>: pressed through the accessibility API, in the test's own
    # process -- by its id, since a second copy of Olai may be running with the same name.
    osascript -e "tell application \"System Events\" to tell (first process whose unix id is $OLAI_PID) to click menu item \"$2\" of menu 1 of menu bar item \"$1\" of menu bar 1" >/dev/null 2>&1
}
view_menu() { menu_item View "$1"; }

# Centre of an element, for the checks that compare positions.
middle_y() { ax frame "$1" 0 | awk '{print int($2 + $4 / 2)}'; }

launch() {
    # launch [extra arguments]: a fresh test instance, its pid exported for the driver.
    [ -n "${OLAI_PID:-}" ] && kill "$OLAI_PID" 2>/dev/null && sleep 1
    "$app/Contents/MacOS/Olai" -OlaiUITesting "$@" >>"$out/app.log" 2>&1 &
    export OLAI_PID=$!
    settle 6
    for _ in 1 2 3 4 5; do
        [ "$(count '=folder:/Work')" -ge 1 ] 2>/dev/null && break
        ax reopen >/dev/null; settle 2
    done
    ax activate >/dev/null
    settle
}

# ---------------------------------------------------------------------------------------

if ! "$driver" trusted >/dev/null 2>&1; then
    echo "This process is not allowed to control the computer (Accessibility), so no check"
    echo "could mean anything. Grant it in System Settings > Privacy & Security > Accessibility."
    exit 2
fi

echo "Olai UI smoke test"
echo "  app:    $app ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null))"
echo "  macOS:  $(sw_vers -productVersion)"
echo "  output: $out"
echo

launch

echo "Layout"
check "the sidebar shows the folders"           "$(count '=folder:/Work')" 1
check "and the pages at the top level"          "$(count '=page:/Inbox')" 1
check "pinned pages have a section of their own" "$(count '=page:pinned/Kickoff')" 1
check "folders start closed"                    "$(count '=page:/Work/Roadmap')" 0
check "no page open on a clean start"           "$(atLeast "$(count 'No page open')" 1)" yes

echo "Folders"
ax click "=folder:/Work" 0 >/dev/null; settle
check "clicking a folder opens it"              "$(count '=page:/Work/Roadmap')" 1
check "with its subfolders inside"              "$(count '=folder:/Work/Q3')" 1
ax click "=folder:/Work" 0 >/dev/null; settle
check "clicking it again closes it"             "$(count '=page:/Work/Roadmap')" 0
ax click "=folder:/Personal" 0 >/dev/null; settle
check "each folder holds its own pages"         "$(count '=page:/Personal/Groceries')" 1

echo "Opening pages"
ax click "=page:/Inbox" 0 >/dev/null; settle
check "clicking a page opens it"                "$(title)" "Inbox"
check "one page open shows no tab bar"          "$(count 'AXButton:Close ')" 0
ax click "=page:/Personal/Groceries" 0 >/dev/null; settle
check "another click shows that page instead"   "$(title)" "Groceries"
check "rather than piling up tabs"              "$(count 'AXButton:Close ')" 0
ax rightclick "=page:/Inbox" 0 >/dev/null; settle 0.8
ax press "AXMenuItem:Open in New Tab" 0 >/dev/null; settle
check "Open in New Tab adds a tab"              "$(count 'AXButton:Close ')" 2
check "the sidebar marks the page in front"     "$(ax value '=page:/Inbox' 0)" "selected"

echo "Tabs"
ax press "=tab:Groceries" 0 >/dev/null; settle
check "pressing a tab switches to it"           "$(title)" "Groceries"
ax click "=tab:Inbox" 0 >/dev/null; settle
check "clicking a tab switches to it"           "$(title)" "Inbox"
check "and the sidebar follows"                 "$(ax value '=page:/Inbox' 0)" "selected"
ax click "AXButton:Close Inbox" 0 >/dev/null; settle
check "clicking a tab's close button closes it" "$(count 'AXButton:Close ')" 0
check "closing the front tab shows its neighbour" "$(title)" "Groceries"
ax rightclick "=page:pinned/Kickoff" 0 >/dev/null; settle 0.8
ax press "AXMenuItem:Open in New Tab" 0 >/dev/null; settle
ax rightclick "=page:/Inbox" 0 >/dev/null; settle 0.8
ax press "AXMenuItem:Open in New Tab" 0 >/dev/null; settle
check "three tabs open"                         "$(count 'AXButton:Close ')" 3
ax rightclick "=tab:Kickoff" 0 >/dev/null; settle
ax press "AXMenuItem:Close Others" 0 >/dev/null; settle
check "Close Others leaves one page"            "$(count 'AXButton:Close ')" 0
check "the page kept is the one right-clicked"  "$(title)" "Kickoff"

echo "One editor for every tab"
ax click "=page:/Inbox" 0 >/dev/null; settle
ax rightclick "=page:/Personal/Groceries" 0 >/dev/null; settle 0.8
ax press "AXMenuItem:Open in New Tab" 0 >/dev/null; settle
ax click "=tab:Inbox" 0 >/dev/null; settle
ax click "editor/AXStaticText:Loose thoughts" 0 >/dev/null; settle 0.5
ax key 124 cmd >/dev/null; ax type " zebra" >/dev/null
# Straight to the other tab, inside the half-second the editor waits before saving.
ax click "=tab:Groceries" 0 >/dev/null; settle 1.5
check "an edit is not carried to the next tab"  "$(count 'editor/zebra')" 0
check "the next tab shows its own page"         "$(atLeast "$(count 'editor/Milk')" 1)" yes
ax key 6 cmd >/dev/null; settle                   # cmd-Z on the page just switched to
check "undo does not reach into the other page" "$(atLeast "$(count 'editor/Milk')" 1)" yes
ax click "=tab:Inbox" 0 >/dev/null; settle
check "the edit was saved to its own page"      "$(atLeast "$(count 'editor/zebra')" 1)" yes
ax key 6 cmd >/dev/null; settle

echo "Creating"
ax click "=folder:/Work" 0 >/dev/null; settle     # open, and select it
ax press "AXButton:=New Page" 0 >/dev/null; settle
check "New Page goes in the selected folder"    "$(count '=page:/Work/Untitled')" 1
check "and is selected there"                   "$(ax value '=page:/Work/Untitled' 0)" "selected"
roadmap_y=$(middle_y '=page:/Work/Roadmap'); new_y=$(middle_y '=page:/Work/Untitled')
check "at the bottom of the folder"             "$(atLeast "$new_y" "$((roadmap_y + 1))")" yes
ax type "Meeting notes" >/dev/null; settle 1
check "its title is ready to type"              "$(count '=page:/Work/Meeting notes')" 1
ax key 36 >/dev/null; settle 0.5                  # Return goes on to the page
ax type "First line" >/dev/null; settle
check "Return moves on to the page"             "$(atLeast "$(count 'editor/First line')" 1)" yes
ax rightclick "=folder:/Personal" 0 >/dev/null; settle 1
ax press "AXMenuItem:=New Page" 0 >/dev/null; settle
check "a folder's own New Page uses that folder" "$(count '=page:/Personal/Untitled')" 1
ax type "Shopping" >/dev/null; settle 1
ax click "=page:/Inbox" 0 >/dev/null; settle
ax key 45 cmd >/dev/null; settle                  # cmd-N beside a top-level page
check "⌘N beside a page goes in its folder"     "$(count '=page:/Untitled')" 1
inbox_y=$(middle_y '=page:/Inbox'); new_y=$(middle_y '=page:/Untitled')
check "at the bottom, not somewhere in between" "$(atLeast "$new_y" "$((inbox_y + 1))")" yes
ax type "Loose page" >/dev/null; settle 1
blank_y=$(ax frame '=page:/Loose page' 0 | awk '{print int($2 + $4 + 40)}')
blank_x=$(ax frame '=page:/Loose page' 0 | awk '{print int($1 + 40)}')
ax clickat "$blank_x" "$blank_y" >/dev/null; settle
ax press "AXButton:=New Folder" 0 >/dev/null; settle
ax type "Smoke" >/dev/null; ax key 36 >/dev/null; settle
check "with nothing selected, a folder goes on top" "$(count '=folder:/Smoke')" 1
ax click "=folder:/Work" 0 >/dev/null; settle     # closes it, selects it
ax key 45 cmd,shift >/dev/null; settle
ax type "Sub" >/dev/null; ax key 36 >/dev/null; settle
check "⇧⌘N makes a folder in the selected one"  "$(count '=folder:/Work/Sub')" 1

echo "Moving"
ax drag "=page:/Loose page" "=folder:/Smoke" >/dev/null; settle 1.5
check "dragging a page onto a folder moves it"  "$(count '=page:/Smoke/Loose page')" 1
ax drag "=page:/Inbox" "=folder:/Personal" >/dev/null; settle 1.5
errands_y=$(middle_y '=page:/Personal/Errands'); moved_y=$(middle_y '=page:/Personal/Inbox')
check "and puts it at the bottom of the folder" "$(atLeast "${moved_y:-0}" "$((errands_y + 1))")" yes
ax rightclick "=page:/Personal/Inbox" 0 >/dev/null; settle 1
ax press "AXMenuItem:=Move to" 0 >/dev/null; settle 0.6
ax press "AXMenuItem:=Top Level" 0 >/dev/null; settle
check "Move to > Top Level moves it back"       "$(count '=page:/Inbox')" 1

echo "Hiding the sidebar"
view_menu "Sidebar"; settle
check "View > Sidebar hides it"                 "$(count '=folder:/Work')" 0
check "the binder tabs stand in for it"         "$(atLeast "$(count 'AXButton:=Personal')" 1)" yes
check "hiding is remembered as a preference"    "$(defaults read "$prefs" layout.showFolders 2>/dev/null)" 0
ax press "AXButton:=Personal" 0 >/dev/null; settle
check "a binder tab brings it back at that folder" "$(ax value '=folder:/Personal' 0)" "expanded"

echo "Toolbar fits"
inside() {
    # inside <element>: is its right edge within the window's?
    local right edge
    right=$(ax frame "$1" 0 | awk '{print int($1 + $3)}')
    edge=$(ax maxx)
    [ -n "$right" ] && [ "$right" -le "$edge" ] && echo yes || echo no
}
ax click "=page:pinned/Kickoff" 0 >/dev/null; settle
ax resize 1200 760 >/dev/null; settle
view_menu "Sidebar"; settle 1.5
page_right=$(ax frame "AXWebArea:" 0 | awk '{print int($1 + $3)}')
check "the page fills the pane"                 "$(atLeast "$((page_right + 30))" "$(ax maxx)")" yes
check "room to spare: every control in one row" "$(count 'AXMenuButton:More')" 0
check "room to spare: the bell is in the window" "$(inside 'AXButton:task')" yes
view_menu "Sidebar"; settle 1
ax resize 920 760 >/dev/null; settle 1.5
check "tight: extras move into More"            "$(count 'AXMenuButton:More')" 1
check "tight: checklist still in the row"      "$(inside 'AXButton:Checklist')" yes
check "tight: the bell still in the row"       "$(inside 'AXButton:task')" yes
ax press "AXMenuButton:More" 0 >/dev/null; settle 0.6
check "More offers what left the row"           "$(atLeast "$(count 'AXMenuItem:Mind Map')" 1)" yes
ax key 53 >/dev/null; settle 0.5                  # Escape
ax resize 900 700 >/dev/null; settle 1.5          # the window's minimum, sidebar showing
check "at the smallest window, More is visible" "$(inside 'AXMenuButton:More')" yes
check "and so is the bell"                      "$(inside 'AXButton:task')" yes
ax resize 1200 760 >/dev/null; settle 1.5

echo "Toolbar"
ax click "=page:pinned/Kickoff" 0 >/dev/null; settle
ax click "editor/AXStaticText:for the quarter" 0 >/dev/null; settle
ax click "AXButton:Checklist" 0 >/dev/null; settle
check "Checklist turns the line into a task"    "$(ax value 'AXButton:Checklist' 0)" "on"
ax key 6 cmd >/dev/null; settle                   # cmd-Z
check "and undo takes it back"                  "$(ax value 'AXButton:Checklist' 0)" "off"
ax press "AXMenuButton:Paragraph Style" 0 >/dev/null; settle 0.6
ax press "AXMenuItem:Heading 2" 0 >/dev/null; settle
check "the style menu makes a heading"          "$(ax value 'AXMenuButton:Paragraph Style' 0)" "Heading 2"
ax press "AXMenuButton:Paragraph Style" 0 >/dev/null; settle 0.6
ax press "AXMenuItem:Body" 0 >/dev/null; settle
check "and Body turns it back"                  "$(ax value 'AXMenuButton:Paragraph Style' 0)" "Body"
ax key 0 cmd >/dev/null; settle 0.5               # cmd-A
ax press "AXMenuButton:Text Colour" 0 >/dev/null; settle 0.6
ax press "AXMenuItem:Red" 0 >/dev/null; settle
check "text colour applies"                     "$(ax value 'AXMenuButton:Text Colour' 0)" "Red"
ax key 6 cmd >/dev/null; settle
ax click "AXButton:Bold" 0 >/dev/null; settle
check "Bold lights up when applied"             "$(ax value 'AXButton:Bold' 0)" "on"
ax key 6 cmd >/dev/null; settle
ax click "editor/AXStaticText:for the quarter" 0 >/dev/null; settle 0.5
ax key 0 cmd >/dev/null; settle 0.5
ax press "AXMenuButton:Highlight" 0 >/dev/null; settle 0.6
ax press "AXMenuItem:Green" 0 >/dev/null; settle
check "highlight takes a colour"                "$(ax value 'AXMenuButton:Highlight' 0)" "Green"
ax key 6 cmd >/dev/null; settle
# Mind Map sits in the row only with room for it: the CI screen is 1024 points wide.
view_menu "Sidebar"; settle 1.5
ax press "AXButton:Mind Map" 0 >/dev/null; settle 1.5
check "Mind Map switches the page to a map"     "$(ax value 'AXButton:Back to the Page' 0)" "on"
ax press "AXButton:Back to the Page" 0 >/dev/null; settle
check "and back to the page"                    "$(ax value 'AXButton:Mind Map' 0)" "off"
view_menu "Sidebar"; settle 1.5

echo "Reminders"
ax click "editor/AXStaticText:for the quarter" 0 >/dev/null; settle
ax click "AXButton:Make this a task" 0 >/dev/null; settle 1.5
check "the bell works away from a checklist"    "$(atLeast "$(count 'AXButton:Cancel')" 1)" yes
ax press "AXButton:Cancel" 0 >/dev/null; settle
ax key 6 cmd >/dev/null; settle

echo "Scheduled tasks"
ax click "=page:/Personal/Errands" 0 >/dev/null; settle
check "a scheduled task shows its due date"     "$(count 'editor/AXStaticText:25 Sep')" 1
ax click "editor/AXStaticText:Call the bank" 0 >/dev/null; settle 0.5
ax key 124 cmd >/dev/null; settle 0.3            # cmd-Right: end of the line
ax key 36 >/dev/null; settle 0.5                  # Return
ax type "Buy stamps" >/dev/null; settle
check "Enter makes a new task"                  "$(count 'editor/AXStaticText:Buy stamps')" 1
check "and it does not inherit the reminder"    "$(count 'editor/AXStaticText:25 Sep')" 1
ax key 6 cmd >/dev/null; ax key 6 cmd >/dev/null; settle

echo "Templates"
ax click "=folder:/Personal" 0 >/dev/null; settle  # select it (closes it too)
ax press "AXMenuButton:Templates and Import" 0 >/dev/null; settle 0.8
ax press "AXMenuItem:Weekly page" 0 >/dev/null; settle 1.5
check "the weekly template titles a week"      "$(title | cut -c1-8)" "Week of "
check "and lays out its sections"              "$(atLeast "$(count 'editor/AXStaticText:Priorities')" 1)" yes
check "in the selected folder"                 "$(atLeast "$(count 'page:/Personal/Week of')" 1)" yes

echo "Page and folder menus"
ax rightclick "=page:/Inbox" 0 >/dev/null; settle 1
ax press "AXMenuItem:Pin" 0 >/dev/null; settle
check "Pin adds it to Pinned"                  "$(count '=page:pinned/Inbox')" 1
ax rightclick "=page:/Work/Meeting notes" 0 >/dev/null; settle 1
ax press "AXMenuItem:Rename" 0 >/dev/null; settle 0.8
ax key 0 cmd >/dev/null; ax type "Notes v2" >/dev/null; ax key 36 >/dev/null; settle
check "Rename renames the page"                "$(count '=page:/Work/Notes v2')" 1
ax rightclick "=page:/Work/Roadmap" 0 >/dev/null; settle 1
ax press "AXMenuItem:Archive" 0 >/dev/null; settle
check "Archive takes it out of its folder"     "$(count '=page:/Work/Roadmap')" 0
# Collapsed first, so the Archive section is on screen on a short display too.
ax press "AXButton:=Collapse All" 0 >/dev/null; settle
ax press "AXButton:=Archive" 0 >/dev/null; settle
check "and into the Archive"                   "$(count '=archived:Roadmap')" 1
ax rightclick "=archived:Roadmap" 0 >/dev/null; settle 1
ax press "AXMenuItem:=Unarchive" 0 >/dev/null; settle
ax press "=folder:/Work" 0 >/dev/null; settle
check "Unarchive puts it back in its folder"    "$(count '=page:/Work/Roadmap')" 1
ax rightclick "=folder:/Personal" 0 >/dev/null; settle 1.2
check "a folder offers Tag Colour"             "$(atLeast "$(count 'AXMenuItem:Tag Colour')" 1)" yes
ax key 53 >/dev/null; settle 0.5
ax rightclick "=page:/Work/Notes v2" 0 >/dev/null; settle 1
ax press "AXMenuItem:Delete" 0 >/dev/null; settle 0.8
ax press "AXButton:Delete" 0 >/dev/null; settle
check "Delete, once confirmed, deletes"        "$(count '=page:/Work/Notes v2')" 0

echo "Search"
ax click "AXTextField:Search" 0 >/dev/null; settle 0.5
ax type "Groc" >/dev/null; settle
check "the search field keeps every letter"     "$(ax value 'AXTextField:Search' 0)" "Groc"
check "search lists what matches"               "$(count '=result:Groceries')" 1
check "and only that"                           "$(count 'AXButton:result:')" 1
ax click "=result:Groceries" 0 >/dev/null; settle
check "a result opens its page"                 "$(title)" "Groceries"

echo "A library the size of a real one"
# A thousand pages: what a OneNote export brings. Tab switching took three seconds at this
# size and under a second with the six-page fixture, which is how it passed every check.
launch -OlaiUITestingLarge
ax click "=folder:/Notebook 1" 0 >/dev/null; settle
ax click "=page:/Notebook 1/Page 1-2" 0 >/dev/null; settle
ax rightclick "=page:/Notebook 1/Page 1-5" 0 >/dev/null; settle 0.8
ax press "AXMenuItem:Open in New Tab" 0 >/dev/null; settle 1.5
marks=$(grep -c olai-perf "$out/app.log")
for _ in 1 2 3; do
    ax click "=tab:Page 1-2" 0 >/dev/null; settle 1
    ax click "=tab:Page 1-5" 0 >/dev/null; settle 1
done
# From the click reaching the app to the editor saying the page is in, by the app's own
# clock: the driver's polling would slow the thing it measures.
slowest=$(grep olai-perf "$out/app.log" | tail -n +"$((marks + 1))" \
    | awk '{for (i = 1; i <= NF; i++) if ($i == "olai-perf") { t = $(i+1); e = $(i+2) }
            if (e == "activate") start = t; else if (e == "loaded" && start) { d = t - start; if (d > max) max = d; start = 0 } }
           END { print int(max) }')
echo "  slowest tab switch: ${slowest} ms"
check "a tab switch takes under half a second" "$(atLeast 500 "${slowest:-9999}")" yes
check "and shows the right page"               "$(atLeast "$(count 'editor/Marker Page 1-5')" 1)" yes

kill "$OLAI_PID" 2>/dev/null

echo
echo "$passed passed, $failed failed.  Screenshots: $out"
[ "$failed" -eq 0 ]
