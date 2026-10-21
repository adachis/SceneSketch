#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
cd "$PROJECT_ROOT"
if [[ ! -f Resources/StoryboardStyle.safetensors && -f ../LoRA/StoryboardStyle.safetensors ]]; then
  mkdir -p Resources
  cp ../LoRA/StoryboardStyle.safetensors Resources/StoryboardStyle.safetensors
fi
if [[ ! -f Resources/StoryboardStyle.safetensors ]]; then
  echo "Missing Resources/StoryboardStyle.safetensors" >&2
  exit 1
fi
xcodegen generate
mkdir -p Storyboard.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
cp Package.resolved Storyboard.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
BUILD_ROOT="${STORYBOARD_DERIVED_DATA:-$PROJECT_ROOT/build}"
xcodebuild -project Storyboard.xcodeproj -scheme Storyboard -configuration Release \
  -derivedDataPath "$BUILD_ROOT" -onlyUsePackageVersionsFromResolvedFile \
  -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO build
APP_PATH="$BUILD_ROOT/Build/Products/Release/SceneSketch.app"
SIGN_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/storyboard-sign.XXXXXX")"
trap 'rm -rf "$SIGN_ROOT"' EXIT
STAGED_APP="$SIGN_ROOT/SceneSketch.app"
ditto --norsrc --noextattr "$APP_PATH" "$STAGED_APP"
xattr -cr "$STAGED_APP"
SIGN_IDENTITY="${STORYBOARD_SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$STAGED_APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$STAGED_APP"
fi
codesign --verify --deep --strict "$STAGED_APP"
mkdir -p "$PROJECT_ROOT/dist"
ditto --norsrc --noextattr -c -k --keepParent "$STAGED_APP" "$PROJECT_ROOT/dist/SceneSketch.zip"
echo "Built $PROJECT_ROOT/dist/SceneSketch.zip"
