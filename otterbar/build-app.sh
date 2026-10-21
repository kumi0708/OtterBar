#!/bin/bash
# OtterBar.app をビルドする（ad-hoc 署名・Apple Silicon / Intel 両対応）。
#   otterbar/build-app.sh             → otterbar/dist/OtterBar.app
#   otterbar/build-app.sh --install   → ~/Applications/OtterBar.app にもコピー
#   otterbar/build-app.sh --zip       → otterbar/dist/OtterBar.zip（配布用）も作る
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
derived="$here/.build"

swift "$here/tools/render_otter.swift" "$here/frames" \
    --assets "$repo/LocalPackage/Sources/UserInterface/Resources/Media.xcassets/Runners" >/dev/null

xcodebuild -project "$repo/RunCatNeo.xcodeproj" -scheme RunCatNeo -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$derived" \
    -skipPackagePluginValidation -skipMacroValidation \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    build | grep -E "error:|\*\* BUILD" || true

app="$derived/Build/Products/Release/OtterBar.app"
[ -d "$app" ] || { echo "build failed" >&2; exit 1; }
rm -rf "$here/dist"
mkdir -p "$here/dist"
cp -R "$app" "$here/dist/"
echo "built: $here/dist/OtterBar.app"

for option in "$@"; do
    case "$option" in
        --install)
            mkdir -p "$HOME/Applications"
            rm -rf "$HOME/Applications/OtterBar.app"
            cp -R "$app" "$HOME/Applications/"
            echo "installed: $HOME/Applications/OtterBar.app"
            ;;
        --zip)
            (cd "$here/dist" && ditto -c -k --keepParent OtterBar.app OtterBar.zip)
            echo "zipped: $here/dist/OtterBar.zip"
            ;;
    esac
done
