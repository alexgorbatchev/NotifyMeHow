bundle_id := "com.alexgorbatchev.notifymehow"
# Bundle identifier of upstream NotifyMeHow builds, quit so both never hide notifications at once
upstream_bundle_id := "com.motleywoods.NotifyMeHow"
app := "NotifyMeHow.app"
# A stable signing identity keeps the Accessibility permission across rebuilds
signing_identity := env("NOTIFYMEHOW_SIGNING_IDENTITY", "Developer ID Application: Alex Gorb (4XCZD8P4CJ)")

default:
    @just --list

# Build the release app bundle into NotifyMeHow.app
build:
    CODESIGN_IDENTITY="{{ signing_identity }}" ./create-app.sh release

# Run the test suite
test:
    swift test

# Rebuild, then replace any running NotifyMeHow with the local build using notifymehow.local.json
run: build quit apply-local-config
    open {{ app }}

# Clear NotifyMeHow's Accessibility permission so the next launch asks again
reset-permissions:
    tccutil reset Accessibility {{ bundle_id }}

# Quit any running NotifyMeHow (this fork or upstream) and wait for it to exit
quit:
    #!/usr/bin/env bash
    set -euo pipefail
    for id in {{ bundle_id }} {{ upstream_bundle_id }}; do
        [[ -z "$(lsappinfo find bundleid="$id")" ]] && continue
        echo "Quitting $id"
        osascript -e "tell application id \"$id\" to quit"
        for _ in {1..50}; do
            [[ -z "$(lsappinfo find bundleid="$id")" ]] && continue 2
            sleep 0.1
        done
        echo "$id did not quit within 5s" >&2
        exit 1
    done

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
