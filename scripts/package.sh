#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-"$ROOT/dist"}"
DERIVED="${ROOT}/.derived"

mkdir -p "$DEST"

xcodebuild \
  -project "$ROOT/QuotaBar.xcodeproj" \
  -scheme QuotaBar \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  MARKETING_VERSION=0.0.8 \
  CURRENT_PROJECT_VERSION=0.0.8 \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO \
  build

APP="$(find "$DERIVED/Build/Products/Release" -maxdepth 1 -name "QuotaBar.app" -type d | head -n 1)"
if [[ -z "$APP" ]]; then
  echo "error: QuotaBar.app was not produced" >&2
  exit 1
fi

rm -rf "$DEST/QuotaBar.app"
cp -R "$APP" "$DEST/QuotaBar.app"
codesign --force --deep --sign - "$DEST/QuotaBar.app"
ditto -c -k --keepParent "$DEST/QuotaBar.app" "$DEST/QuotaBar.zip"

echo "Built:"
echo "  $DEST/QuotaBar.app"
echo "  $DEST/QuotaBar.zip"
echo
echo "First run on another Mac:"
echo "  xattr -dr com.apple.quarantine \"$DEST/QuotaBar.app\""
echo "  Then open the app (System Settings → Privacy & Security → Open Anyway if Gatekeeper blocks it)."
