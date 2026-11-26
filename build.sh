#!/bin/sh
set -e
cd "$(dirname "$0")"
swiftc -O main.swift -o /tmp/walkpad-test && /tmp/walkpad-test --selftest
APP=WalkPad.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift -o "$APP/Contents/MacOS/WalkPad"
cp Info.plist "$APP/Contents/"
mkdir -p "$APP/Contents/Resources" /tmp/AppIcon.iconset docs
swift icon.swift docs/icon.png
for n in 16 32 128 256 512; do
  sips -z $n $n docs/icon.png --out /tmp/AppIcon.iconset/icon_${n}x${n}.png >/dev/null
  sips -z $((n*2)) $((n*2)) docs/icon.png --out /tmp/AppIcon.iconset/icon_${n}x${n}@2x.png >/dev/null
done
iconutil -c icns /tmp/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign -s - --force "$APP"
pkill -x WalkPad || true
rm -rf ~/Applications/"$APP" && mkdir -p ~/Applications && cp -R "$APP" ~/Applications/
open ~/Applications/"$APP"
