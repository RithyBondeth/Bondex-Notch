/// A deliberately small command surface shared by App Intents and the running
/// app. Intents can request only these validated actions rather than receiving
/// arbitrary access to individual services.
enum AppIntentCommand {
    enum Action: String {
        case automaticProfiles
        case activateProfile
        case createCapture
        case showWidget
        case startFocus
    }
}
