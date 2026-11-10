# One-time setup on Windows (PowerShell): creates the Android and web folders, adds the
# Internet permission (needed to download the Plus Jakarta Sans font), lets password-reset
# links open the app, and installs packages.
# Run from the project folder:  powershell -ExecutionPolicy Bypass -File .\setup.ps1
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
flutter create --platforms=android,web --org ph.crafthive --project-name crafthive .
$manifest = "android\app\src\main\AndroidManifest.xml"
$text = Get-Content $manifest -Raw
if ($text -notmatch "android.permission.INTERNET") {
  $text = $text -replace "<application", "<uses-permission android:name=`"android.permission.INTERNET`"/>`r`n    <application"
}
$text = $text -replace 'android:label="crafthive"', 'android:label="CraftHive"'
# Password-reset links from the email open the app (Supabase Auth)
if ($text -notmatch "ph.crafthive.app") {
  $link = @"
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="ph.crafthive.app" android:host="reset-password"/>
            </intent-filter>
            <meta-data android:name="flutter_deeplinking_enabled" android:value="false"/>
        </activity>
"@
  $text = $text -replace '        </activity>', $link
}
Set-Content -Path $manifest -Value $text -NoNewline
flutter pub get
Write-Host "Done. Run: flutter run   (or: flutter build apk --release)"
