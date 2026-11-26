#!/bin/sh
set -e
cd "$(dirname "$0")"
swiftc -O main.swift -o /tmp/walkpad-test && /tmp/walkpad-test --selftest
APP=WalkPad.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift -o "$APP/Contents/MacOS/WalkPad"
cp Info.plist "$APP/Contents/"
codesign -s - --force "$APP"
pkill -x WalkPad || true
rm -rf ~/Applications/"$APP" && mkdir -p ~/Applications && cp -R "$APP" ~/Applications/
open ~/Applications/"$APP"
