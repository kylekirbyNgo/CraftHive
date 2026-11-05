# One-time setup on Windows (PowerShell): creates the Android and web folders, adds the
# Internet permission (needed to download the Plus Jakarta Sans font), and installs packages.
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
Set-Content -Path $manifest -Value $text -NoNewline
flutter pub get
Write-Host "Done. Run: flutter run   (or: flutter build apk --release)"
