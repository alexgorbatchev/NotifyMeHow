bundle_id := "com.motleywoods.NotifyMeHow"
app := "NotifyMeHow.app"

default:
    @just --list

# Build the release app bundle into NotifyMeHow.app
build:
    ./create-app.sh release

# Run the test suite
test:
    swift test

# Rebuild, then replace any running NotifyMeHow with the local build using notifymehow.local.json
run: build quit reset-permissions apply-local-config
    open {{ app }}

# Clear NotifyMeHow's Accessibility permission so the next launch asks again. Each ad-hoc
# signed build is trusted per binary, so a grant for a previous build no longer applies.
reset-permissions:
    tccutil reset Accessibility {{ bundle_id }}

# Quit any running NotifyMeHow (installed or local build) and wait for it to exit
quit:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ -z "$(lsappinfo find bundleid={{ bundle_id }})" ]] && exit 0
    echo "Quitting {{ bundle_id }}"
    osascript -e 'tell application id "{{ bundle_id }}" to quit'
    for _ in {1..50}; do
        [[ -z "$(lsappinfo find bundleid={{ bundle_id }})" ]] && exit 0
        sleep 0.1
    done
    echo "{{ bundle_id }} did not quit within 5s" >&2
    exit 1

# Replace settings, styles and rules with notifymehow.local.json (run while NotifyMeHow is not running)
apply-local-config:
    {{ app }}/Contents/MacOS/NotifyMeHow --import-settings notifymehow.local.json

# Send system notifications for NotifyMeHow to restyle: a default-style stack, an slk-rule match, then reflow as they expire
test-notifications:
    osascript -e 'display notification "Short body for the first banner." with title "NotifyMeHow test 1"'
    sleep 1
    osascript -e 'display notification "A longer body that should wrap onto a second line so the stack mixes banner heights and the reflow animation is easy to see." with title "NotifyMeHow test 2 with a longer title"'
    sleep 1
    osascript -e 'display notification "Matches the slk rule and uses the slk style." with title "[slk] NotifyMeHow test 3"'
