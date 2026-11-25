/// The app's version as in pubspec.yaml (`version:`), attached to question
/// reports. A release build may pass `--dart-define=DILMAC_VERSION=…`;
/// test/app_version_test.dart keeps the default equal to pubspec.yaml.
const appVersion = String.fromEnvironment('DILMAC_VERSION', defaultValue: '0.1.0+2');
