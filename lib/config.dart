/// Pixabay API key. Supplied at build time (--dart-define=PIXABAY_KEY=...) from the
/// GitHub secret of the same name, so it is not stored in the repository.
const String kPixabayKey = String.fromEnvironment('PIXABAY_KEY');

/// AI image API key (API.market). Supplied at build time from the GitHub secret
/// AI_IMAGE_KEY. NOTE: a key built into an APK can be extracted, so only share
/// builds publicly once requests go through a small backend instead.
const String kAiImageKey = String.fromEnvironment('AI_IMAGE_KEY');
