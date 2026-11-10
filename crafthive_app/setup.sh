#!/usr/bin/env bash
# One-time setup on macOS/Linux: creates the Android and web folders, adds the
# Internet permission (needed to download the Plus Jakarta Sans font), lets password-reset
# links open the app, and installs packages.
set -e
cd "$(dirname "$0")"
flutter create --platforms=android,web --org ph.crafthive --project-name crafthive .
MANIFEST=android/app/src/main/AndroidManifest.xml
if ! grep -q "android.permission.INTERNET" "$MANIFEST"; then
  sed -i.bak 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$MANIFEST" && rm -f "$MANIFEST.bak"
fi
# Show the app name as "CraftHive" under the icon
sed -i.bak 's#android:label="crafthive"#android:label="CraftHive"#' "$MANIFEST" && rm -f "$MANIFEST.bak"
# Password-reset links from the email open the app (Supabase Auth)
if ! grep -q "ph.crafthive.app" "$MANIFEST"; then
  python3 - "$MANIFEST" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
link = '''            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="ph.crafthive.app" android:host="reset-password"/>
            </intent-filter>
            <meta-data android:name="flutter_deeplinking_enabled" android:value="false"/>
'''
open(p, 'w').write(s.replace('        </activity>', link + '        </activity>', 1))
PY
fi
flutter pub get
echo "Done. Run: flutter run   (or: flutter build apk --release)"
