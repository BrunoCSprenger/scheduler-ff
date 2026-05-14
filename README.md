# Scheduler

A cross-platform Flutter application for sharing availability and coordinating schedules in groups. Built with Firebase backend for real-time data synchronization and authentication.

## Features

- **User Authentication**: Secure authentication using Firebase Auth
- **Group Management**: Create and join groups to share availability
- **Availability Tracking**: Mark your available time slots
- **Real-time Sync**: Cloud Firestore provides instant synchronization across devices
- **Timezone Support**: Automatic timezone handling for global teams
- **Multi-platform**: Runs on Android, iOS, Web, Windows, macOS, and Linux

## Tech Stack

- **Framework**: Flutter 3.11+
- **Backend**: Firebase (Authentication & Cloud Firestore)
- **UI**: Material Design
- **Internationalization**: intl package
- **Time Management**: timezone package

## Prerequisites

- Flutter SDK (3.11.3 or higher)
- Dart SDK (included with Flutter)
- Firebase project with Firestore and Authentication enabled
- Xcode (for iOS development) or Android Studio (for Android development)

## Running in Android Studio

### Prerequisites

- Android Studio installed with Flutter and Dart plugins
- Flutter SDK configured in Android Studio
- Android Device or Emulator

### Steps to Run

1. **Open the Project**
   - Launch Android Studio
   - Select "File" > "Open"
   - Navigate to the scheduler project directory
   - Click "OK" to open the project

2. **Sync Flutter Dependencies**
   - Android Studio will automatically detect it's a Flutter project
   - Wait for gradle sync to complete
   - If prompted, run "Pub get" to install Dart dependencies
   - Alternatively, open the terminal and run `flutter pub get`

3. **Select a Device**
   - In the top toolbar, click the device dropdown
   - Select an Android emulator or connected physical device
   - If no device is available:
     - For emulator: Click "Create Device" and follow the setup wizard
     - For physical device: Enable USB debugging and connect via USB

4. **Run the App**
   - Click the green "Run" button in the toolbar (or press Shift+F10)
   - Alternatively, select "Run" > "Run 'app'" from the menu
   - The app will compile and launch on the selected device

5. **Debug Mode**
   - To run in debug mode with hot reload: Press Ctrl+Alt+Shift+R
   - Breakpoints can be set by clicking on line numbers in the editor
   - Use the Debug panel to inspect variables and step through code

### Firebase Setup for Android

The Firebase configuration file `google-services.json` is already included in `android/app/`. The app will automatically connect to your Firebase project using this configuration.

## Project Structure

```
lib/
├── main.dart               # Entry point
├── firebase_options.dart   # Firebase configuration
├── app/                    # App-level widgets
├── screens/                # UI screens
├── models/                 # Data models
├── services/               # Business logic & Firebase services
├── auth/                   # Authentication logic
├── data/                   # Data layer
└── utils/                  # Utility functions
```

## Key Services

- **AuthService**: Handles user authentication
- **AvailabilityService**: Manages user availability data
- **FirestoreService**: Cloud Firestore operations

## Security

- Firestore security rules are configured in `firestore.rules`
- Authentication is required for all user operations
- Data is encrypted in transit via Firebase

## Building for Production

```bash
# Android
flutter build apk
flutter build appbundle

# iOS
flutter build ios

# Web
flutter build web

# Desktop
flutter build windows
flutter build macos
flutter build linux
```

## Testing

```bash
flutter test
```

## Contributing

1. Create a feature branch
2. Commit your changes
3. Push to the branch
4. Submit a pull request

## License

This project is proprietary and confidential.

## Resources

- [Flutter Documentation](https://flutter.dev/docs)
- [Firebase Documentation](https://firebase.google.com/docs)
- [Cloud Firestore Guide](https://firebase.google.com/docs/firestore)
- [Firebase Auth Guide](https://firebase.google.com/docs/auth)
