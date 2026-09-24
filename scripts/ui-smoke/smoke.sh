#!/bin/bash
# End-to-end UI smoke test. Launches Olai in test mode -- an in-memory store of fixture
# notes and a preferences suite of its own, so nothing here can touch a real library or
# the Markdown mirror -- then drives it the way a person does and checks each result.
#
#   scripts/ui-smoke/smoke.sh [path/to/Olai.app] [output-dir]
#
# Run it against the notarised build before shipping, not only a Debug build: that is
# the thing people install. Needs Accessibility permission for the terminal running it.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
app="${1:-$here/../../build/dd/Build/Products/Debug/Olai.app}"
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

frontmost() { osascript -e 'tell application "System Events" to name of first application process whose frontmost is true' 2>/dev/null; }

keys_type() {
    [ "$(frontmost)" = "Olai" ] || { echo "REFUSED: Olai is not in front" >&2; return 4; }
    osascript -e "tell application \"System Events\" to keystroke \"$1\"" >/dev/null 2>&1
}

keys_press() {
    [ "$(frontmost)" = "Olai" ] || { echo "REFUSED: Olai is not in front" >&2; return 4; }
    local using=""
    case "$2" in
        cmd) using=" using command down" ;;
        cmd,shift) using=" using {command down, shift down}" ;;
    esac
    osascript -e "tell application \"System Events\" to key code $1$using" >/dev/null 2>&1
}
count() { ax count "$1"; }
title() { ax value "AXTextField:" 0; }
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

view_menu() {
    # The View menu is pressed through the accessibility API too, scoped to Olai.
    osascript -e "tell application \"System Events\" to tell process \"Olai\" to click menu item \"$1\" of menu 1 of menu bar item \"View\" of menu bar 1" >/dev/null 2>&1
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

osascript -e 'tell application "Olai" to quit' >/dev/null 2>&1
for _ in $(seq 1 20); do pgrep -x Olai >/dev/null || break; sleep 0.5; done
pkill -x Olai 2>/dev/null
"$app/Contents/MacOS/Olai" -OlaiUITesting >"$out/app.log" 2>&1 &
settle 6
ax activate >/dev/null
settle

echo "Layout"
check "three columns: folders showing"          "$(atLeast "$(count 'Notebooks')" 1)" yes
check "page list lists every page"              "$(count 'AXStaticText:Groceries')" 1
check "a list preview keeps its items apart"    "$(count 'AXStaticText:MilkBread')" 0
check "a preview skips a repeated title"        "$(count 'AXStaticText:Kickoff')" 1
check "no page open on a clean start"           "$(atLeast "$(count 'No page open')" 1)" yes

echo "Opening pages"
ax click "AXStaticText:=Inbox" 0 >/dev/null; settle
check "clicking a page opens it"                "$(title)" "Inbox"
check "one page open shows no tab bar"          "$(count 'AXButton:Close ')" 0
ax click "AXStaticText:=Roadmap" 0 >/dev/null; settle
check "a second page opens as a tab"            "$(title)" "Roadmap"
check "two tabs, two close buttons"             "$(count 'AXButton:Close ')" 2

echo "Tabs"
ax press "AXButton:Inbox" 0 >/dev/null; settle
check "pressing a tab switches to it"           "$(title)" "Inbox"
ax click "AXButton:Roadmap" 0 >/dev/null; settle
check "clicking a tab switches to it"           "$(title)" "Roadmap"
ax click "AXButton:Close Roadmap" 0 >/dev/null; settle
check "clicking a tab's close button closes it" "$(count 'AXButton:Close ')" 0
check "closing the front tab shows its neighbour" "$(title)" "Inbox"
ax click "AXStaticText:=Kickoff" 0 >/dev/null; settle
ax click "AXStaticText:=Planning" 0 >/dev/null; settle
check "three tabs open"                         "$(count 'AXButton:Close ')" 3
ax rightclick "AXButton:Kickoff" 0 >/dev/null; settle
ax press "AXMenuItem:Close Others" 0 >/dev/null; settle
check "Close Others leaves one page"            "$(count 'AXButton:Close ')" 0
check "the page kept is the one right-clicked"  "$(title)" "Kickoff"

echo "Folders"
ax click "=Personal" 0 >/dev/null; settle
check "a folder lists its own pages"            "$(count 'AXStaticText:Groceries')" 1
check "and not other folders' pages"            "$(count 'AXStaticText:Roadmap')" 0
ax click "AXStaticText:=All Pages" 0 >/dev/null; settle
check "All Pages lists everything again"        "$(count 'AXStaticText:Roadmap')" 1

echo "Hiding columns"
view_menu "Folders"; settle
check "View > Folders hides the folders"        "$(count 'Notebooks')" 0
check "the tag rail stands in for them"         "$(atLeast "$(count 'AXButton:Personal')" 1)" yes
ax press "AXButton:Personal" 0 >/dev/null; settle
check "a rail tab changes folder"               "$(count 'AXStaticText:Roadmap')" 0
shown_x=$(ax frame "AXTextField:" 0 | awk '{print int($1)}')
view_menu "Page List"; settle
hidden_x=$(ax frame "AXTextField:" 0 | awk '{print int($1)}')
# The editor column centres itself once the pane is wider than it, so it moves left by
# less than the page list's width -- but by nothing at all if the list did not go.
check "View > Page List hides the page list"    "$(atLeast "$((shown_x - hidden_x))" 50)" yes
view_menu "Folders"; settle
view_menu "Page List"; settle
check "both come back"                          "$(atLeast "$(count 'Notebooks')" 1)" yes
check "hiding is remembered as a preference"    "$(defaults read "$prefs" layout.showFolders 2>/dev/null)" 1

echo "Toolbar fits"
inside() {
    # inside <element>: is its right edge within the window's?
    local right edge
    right=$(ax frame "$1" 0 | awk '{print int($1 + $3)}')
    edge=$(ax maxx)
    [ -n "$right" ] && [ "$right" -le "$edge" ] && echo yes || echo no
}
ax click "AXStaticText:=Kickoff" 0 >/dev/null; settle
ax resize 1600 900 >/dev/null; settle 1.5
check "wide window: every control in one row"   "$(count 'AXMenuButton:More')" 0
check "wide window: the bell is inside the window" "$(inside 'AXButton:task')" yes
ax resize 1000 760 >/dev/null; settle 1.5
check "narrow window: extras move into More"    "$(count 'AXMenuButton:More')" 1
check "narrow window: checklist still in the row" "$(inside 'AXButton:Checklist')" yes
check "narrow window: the bell still in the row" "$(inside 'AXButton:task')" yes
ax press "AXMenuButton:More" 0 >/dev/null; settle 0.6
check "More offers what left the row"           "$(atLeast "$(count 'AXMenuItem:Mind Map')" 1)" yes
ax key 53 >/dev/null; settle 0.5                  # Escape
ax resize 1200 760 >/dev/null; settle 1.5

echo "Toolbar"
ax click "AXStaticText:=Kickoff" 0 >/dev/null; settle
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

echo "Reminders"
ax click "editor/AXStaticText:for the quarter" 0 >/dev/null; settle
ax click "AXButton:Make this a task" 0 >/dev/null; settle 1.5
check "the bell works away from a checklist"    "$(atLeast "$(count 'AXButton:Cancel')" 1)" yes
ax press "AXButton:Cancel" 0 >/dev/null; settle
ax key 6 cmd >/dev/null; settle

echo "Scheduled tasks"
ax click "AXStaticText:=Errands" 0 >/dev/null; settle
check "a scheduled task shows its due date"     "$(count 'editor/AXStaticText:25 Sep')" 1
ax click "editor/AXStaticText:Call the bank" 0 >/dev/null; settle 0.5
ax key 124 cmd >/dev/null; settle 0.3            # cmd-Right: end of the line
ax key 36 >/dev/null; settle 0.5                  # Return
ax type "Buy stamps" >/dev/null; settle
check "Enter makes a new task"                  "$(count 'editor/AXStaticText:Buy stamps')" 1
check "and it does not inherit the reminder"    "$(count 'editor/AXStaticText:25 Sep')" 1
ax key 6 cmd >/dev/null; ax key 6 cmd >/dev/null; settle

echo "Creating"
before=$(count "AXStaticText:Untitled")
ax press "AXPopUpButton:New Page" 0 >/dev/null; settle
check "New Page opens a new page"               "$(title)" "Untitled"
ax press "AXButton:New Folder" 0 >/dev/null; settle
ax type "Smoke" >/dev/null; ax key 36 >/dev/null; settle
check "New Folder asks for a name and makes it" "$(atLeast "$(count '=Smoke')" 1)" yes

echo "Formatting that needed room"
ax resize 1600 900 >/dev/null; settle 1.5
ax click "AXStaticText:=Kickoff" 0 >/dev/null; settle
ax click "editor/AXStaticText:for the quarter" 0 >/dev/null; settle 0.5
ax key 0 cmd >/dev/null; settle 0.5
ax press "AXMenuButton:Highlight" 0 >/dev/null; settle 0.6
ax press "AXMenuItem:Green" 0 >/dev/null; settle
check "highlight takes a colour"                "$(ax value 'AXMenuButton:Highlight' 0)" "Green"
ax key 6 cmd >/dev/null; settle
ax press "AXButton:Mind Map" 0 >/dev/null; settle 1.5
check "Mind Map switches the page to a map"     "$(ax value 'AXButton:Back to the Page' 0)" "on"
ax press "AXButton:Back to the Page" 0 >/dev/null; settle
check "and back to the page"                    "$(ax value 'AXButton:Mind Map' 0)" "off"
ax resize 1200 760 >/dev/null; settle 1.5

echo "Templates"
ax click "AXStaticText:=All Pages" 0 >/dev/null; settle
ax clickend "AXPopUpButton:New Page" 0 >/dev/null; settle 1
ax press "AXMenuItem:Weekly page" 0 >/dev/null; settle 1.5
check "the weekly template titles a week"      "$(title | cut -c1-8)" "Week of "
check "and lays out its sections"              "$(atLeast "$(count 'editor/AXStaticText:Priorities')" 1)" yes

echo "Page and folder menus"
ax rightclick "AXStaticText:=Inbox" 0 >/dev/null; settle 1
ax press "AXMenuItem:Pin" 0 >/dev/null; settle
check "Pin marks the page"                     "$(atLeast "$(count 'AXImage:Pin')" 2)" yes
ax rightclick "AXStaticText:=Planning" 0 >/dev/null; settle 1
ax press "AXMenuItem:Rename" 0 >/dev/null; settle 0.8
ax key 0 cmd >/dev/null; ax type "Planning v2" >/dev/null; ax key 36 >/dev/null; settle
check "Rename renames the page"                "$(count 'AXStaticText:Planning v2')" 1
ax rightclick "AXStaticText:=Roadmap" 0 >/dev/null; settle 1
ax press "AXMenuItem:Archive" 0 >/dev/null; settle
check "Archive takes it out of the list"       "$(count 'AXStaticText:Roadmap')" 0
ax click "AXStaticText:=Archive" 0 >/dev/null; settle
check "and into the Archive"                   "$(count 'AXStaticText:Roadmap')" 1
ax click "AXStaticText:=All Pages" 0 >/dev/null; settle
ax rightclick "=Personal" 0 >/dev/null; settle 1.2
check "a folder offers Tag Colour"             "$(atLeast "$(count 'AXMenuItem:Tag Colour')" 1)" yes
ax key 53 >/dev/null; settle 0.5
ax rightclick "=Work" 0 >/dev/null; settle 1.2
check "so does one with subfolders"            "$(atLeast "$(count 'AXMenuItem:Tag Colour')" 1)" yes
ax key 53 >/dev/null; settle 0.5
ax rightclick "AXStaticText:Planning v2" 0 >/dev/null; settle 1
ax press "AXMenuItem:Delete" 0 >/dev/null; settle 0.8
ax press "AXButton:Delete" 0 >/dev/null; settle
check "Delete, once confirmed, deletes"        "$(count 'AXStaticText:Planning v2')" 0

echo "Search"
ax click "AXStaticText:=All Pages" 0 >/dev/null; settle
check "before searching, other pages are listed" "$(count 'AXStaticText:Inbox')" 1
ax click "AXTextField:Search all pages" 0 >/dev/null; settle 0.5
ax type "Groc" >/dev/null; settle
check "search narrows the list"                 "$(count 'AXStaticText:Inbox')" 0
check "and finds the match"                     "$(count 'AXStaticText:Groceries')" 1

osascript -e 'tell application "Olai" to quit' >/dev/null 2>&1

echo
echo "$passed passed, $failed failed.  Screenshots: $out"
[ "$failed" -eq 0 ]
