#!/bin/sh
# ./build.sh                 self-test, build build/Deskwalk.app
# ./build.sh install         build, copy to /Applications, launch
# ./build.sh release [x.y.z] bump the version (patch by default), commit, tag and push: CI then publishes it
# ./build.sh publish         (CI) build, GitHub release, update the Homebrew cask
set -e
cd "$(dirname "$0")"
PLIST=Info.plist
TAP=mathieuletyrant/homebrew-tap
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" $PLIST)

if [ "$1" = "release" ]; then
    git diff --quiet && git diff --cached --quiet || { echo "error: commit your changes first"; exit 1; }
    NEW=${2:-$(echo "$VERSION" | awk -F. '{ printf "%d.%d.%d", $1, $2, $3 + 1 }')}
    /usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $NEW" $PLIST
    git commit -qm "chore(release): $NEW" $PLIST
    git tag "v$NEW"
    git push -q && git push -q origin "v$NEW"
    echo "Tagged v$NEW: GitHub Actions builds and publishes it (gh run watch)"
    exit 0
fi

mkdir -p build
swiftc -O main.swift -o build/selftest && build/selftest --selftest
APP=build/Deskwalk.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O main.swift -o "$APP/Contents/MacOS/Deskwalk"
cp $PLIST "$APP/Contents/"
swift icon.swift docs/icon.png
ICONSET=build/AppIcon.iconset
rm -rf $ICONSET && mkdir -p $ICONSET
for n in 16 32 128 256 512; do
    sips -z $n $n docs/icon.png --out $ICONSET/icon_${n}x${n}.png >/dev/null
    sips -z $((n * 2)) $((n * 2)) docs/icon.png --out $ICONSET/icon_${n}x${n}@2x.png >/dev/null
done
iconutil -c icns $ICONSET -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"

if [ "$1" = "install" ]; then
    pkill -x Deskwalk || true
    rm -rf /Applications/Deskwalk.app
    cp -R "$APP" /Applications/
    open /Applications/Deskwalk.app
    echo "Installed /Applications/Deskwalk.app"
fi

if [ "$1" = "publish" ]; then
    ditto -c -k --keepParent "$APP" build/Deskwalk.zip
    SHA=$(shasum -a 256 build/Deskwalk.zip | cut -d' ' -f1)
    gh release create "v$VERSION" build/Deskwalk.zip --title "Deskwalk $VERSION" --generate-notes

    # Versioned cask, so a plain `brew update && brew upgrade` picks the new release up.
    CASK=$(cat <<EOF
cask "deskwalk" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/mathieuletyrant/deskwalk-app/releases/download/v#{version}/Deskwalk.zip"
  name "Deskwalk"
  desc "Drive a WalkingPad from the menu bar and send sessions to Apple Health"
  homepage "https://github.com/mathieuletyrant/deskwalk-app"

  depends_on macos: :tahoe
  depends_on arch: :arm64

  app "Deskwalk.app"

  # Not notarized (no Apple Developer account): drop quarantine so Gatekeeper lets it launch.
  # Done on the staged copy (steps run there), before it moves to /Applications.
  preflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "Deskwalk.app"], chdir: "."
  end

  uninstall quit: "com.mathieu.deskwalk"

  zap trash: "~/Library/Preferences/com.mathieu.deskwalk.plist"
end
EOF
)
    # The tap is another repo: CI writes to it with TAP_TOKEN, a local run with your gh login.
    [ -n "$TAP_TOKEN" ] && export GH_TOKEN="$TAP_TOKEN"
    FILE_SHA=$(gh api "repos/$TAP/contents/Casks/deskwalk.rb" --jq .sha 2>/dev/null || true)
    gh api -X PUT "repos/$TAP/contents/Casks/deskwalk.rb" -f message="feat(deskwalk): $VERSION" \
        -f content="$(printf '%s\n' "$CASK" | base64)" ${FILE_SHA:+-f sha="$FILE_SHA"} >/dev/null
    echo "Published $VERSION. Update with: brew update && brew upgrade"
fi
