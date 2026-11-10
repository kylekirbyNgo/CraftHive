#!/usr/bin/env bash
# One-time setup on macOS/Linux: creates the Android and web folders, adds the
# Internet permission (needed to download the Plus Jakarta Sans font), and installs packages.
set -e
cd "$(dirname "$0")"
flutter create --platforms=android,web --org ph.crafthive --project-name crafthive .
MANIFEST=android/app/src/main/AndroidManifest.xml
if ! grep -q "android.permission.INTERNET" "$MANIFEST"; then
  sed -i.bak 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$MANIFEST" && rm -f "$MANIFEST.bak"
fi
# Show the app name as "CraftHive" under the icon
sed -i.bak 's#android:label="crafthive"#android:label="CraftHive"#' "$MANIFEST" && rm -f "$MANIFEST.bak"
flutter pub get
echo "Done. Run: flutter run   (or: flutter build apk --release)"
