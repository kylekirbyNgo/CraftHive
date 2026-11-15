import 'package:firebase_core/firebase_core.dart';

/// Connection details for the group's Firebase project (chat, online status,
/// notifications and push). Copy them from the Firebase console:
/// Project settings → General → Your apps → the Android app (ph.crafthive.crafthive).
/// See FIREBASE_SETUP.md, step 3.
///
/// These values are meant to be inside the app, like the Supabase anon key:
/// what users may read and write is decided by firebase/firestore.rules and
/// firebase/database.rules.json.
abstract final class FirebaseConfig {
  /// "Web API key" (also in google-services.json: client → api_key → current_key)
  static const apiKey = 'AIzaSyAkpYY-CjnVCAE5ZTZFJYZDrd4vWS-w4_8';

  /// "App ID", e.g. 1:123456789012:android:abc123def456
  static const appId = '1:747307420361:android:5eef891b8e44d24dfa5b18';

  /// "Project number" (google-services.json: project_info → project_number)
  static const messagingSenderId = '747307420361';

  /// "Project ID", e.g. crafthive-group9
  static const projectId = 'crafthive-mobile-app';

  /// Realtime Database URL (Build → Realtime Database, shown above the data),
  /// e.g. https://crafthive-group9-default-rtdb.asia-southeast1.firebasedatabase.app
  static const databaseUrl = 'https://crafthive-mobile-app-default-rtdb.asia-southeast1.firebasedatabase.app';

  static bool get isSet => apiKey.isNotEmpty && appId.isNotEmpty && messagingSenderId.isNotEmpty && projectId.isNotEmpty && databaseUrl.startsWith('https://');

  static FirebaseOptions get options => const FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
        databaseURL: databaseUrl,
      );

  /// True after Firebase started in main(). When false (not set up yet, or in
  /// the automated tests) chats and notifications use the sample data instead.
  static bool ready = false;
}
