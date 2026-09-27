#!/bin/bash
# The update settings Tansu ships with (App/Info.plist, generated from project.yml and committed): the website's feed
# over HTTPS, a 32-byte EdDSA key (the one verify-update.swift checks releases against), a signed feed, disk images
# verified before they are opened, and no system profile. Sparkle is Tansu's only network connection.
source "$(dirname "$0")/lib.sh"
cd "$ROOT"
PLIST=App/Info.plist
value() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true; }
is() { [ "$(value "$1")" = "$2" ]; }
check "the feed is the website's appcast, over HTTPS" is SUFeedURL https://gettansu.vercel.app/appcast.xml
key_bytes() { python3 -c 'import base64, sys; print(len(base64.b64decode(sys.argv[1], validate=True)))' "$(value SUPublicEDKey)"; }
key_ok() { [ "$(key_bytes)" = 32 ]; }
check "SUPublicEDKey is a 32-byte EdDSA public key" key_ok
check "the feed itself must be signed" is SURequireSignedFeed true
check "updates are verified before they are opened" is SUVerifyUpdateBeforeExtraction true
no_profile() { [ "$(value SUEnableSystemProfiling)" != true ]; }
check "Sparkle sends no system profile" no_profile
same_key() { grep -qF "SUPublicEDKey: \"$(value SUPublicEDKey)\"" project.yml; }
check "project.yml carries the same key" same_key
same_feed() { grep -qF "SUFeedURL: $(value SUFeedURL)" project.yml; }
check "project.yml carries the same feed" same_feed
