import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct CaptureEnhancement: Codable, Equatable {
    var title: String
    var summary: String
    var actionItems: [String]
    var tags: [String]

    func normalized(fallbackText: String) -> CaptureEnhancement {
        let fallback = fallbackText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return CaptureEnhancement(
            title: String((cleanTitle.isEmpty ? fallback : cleanTitle).prefix(80)),
            summary: String(cleanSummary.prefix(240)),
            actionItems: cleaned(actionItems, maximumCount: 4, maximumLength: 140),
            tags: cleaned(tags, maximumCount: 3, maximumLength: 24)
        )
    }

    private func cleaned(
        _ values: [String],
        maximumCount: Int,
        maximumLength: Int
    ) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return nil }
            let bounded = String(clean.prefix(maximumLength))
            guard seen.insert(bounded.lowercased()).inserted else { return nil }
            return bounded
        }
        .prefix(maximumCount)
        .map { $0 }
    }
}

enum CaptureIntelligenceAvailability: Equatable {
    case available
    case unavailable(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var explanation: String {
        switch self {
        case .available:
            return "Enhance on device with Apple Intelligence"
        case let .unavailable(reason):
            return reason
        }
    }
}

enum CaptureIntelligenceError: LocalizedError, Equatable {
    case emptyInput
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput: return "Enter something before enhancing it."
        case let .unavailable(reason): return reason
        }
    }
}

@MainActor
final class CaptureIntelligenceService: ObservableObject {
    typealias AvailabilityProvider = @Sendable () -> CaptureIntelligenceAvailability
    typealias EnhancementProvider = @Sendable (String) async throws -> CaptureEnhancement

    @Published private(set) var availability: CaptureIntelligenceAvailability
    @Published private(set) var isEnhancing = false
    @Published private(set) var errorMessage: String?

    private let availabilityProvider: AvailabilityProvider
    private let enhancementProvider: EnhancementProvider

    convenience init() {
        self.init(
            availabilityProvider: { CaptureIntelligenceService.systemAvailability() },
            enhancementProvider: { input in
                try await CaptureIntelligenceService.systemEnhancement(input)
            }
        )
    }

    init(
        availabilityProvider: @escaping AvailabilityProvider,
        enhancementProvider: @escaping EnhancementProvider
    ) {
        self.availabilityProvider = availabilityProvider
        self.enhancementProvider = enhancementProvider
        self.availability = availabilityProvider()
    }

    func refreshAvailability() {
        availability = availabilityProvider()
    }

    func clearError() {
        errorMessage = nil
    }

    func enhance(_ input: String) async -> CaptureEnhancement? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorMessage = CaptureIntelligenceError.emptyInput.localizedDescription
            return nil
        }
        guard availability.isAvailable else {
            errorMessage = availability.explanation
            return nil
        }
        guard !isEnhancing else { return nil }

        isEnhancing = true
        errorMessage = nil
        defer { isEnhancing = false }

        do {
            return try await enhancementProvider(String(text.prefix(6_000)))
                .normalized(fallbackText: text)
        } catch {
            errorMessage = error.localizedDescription
            refreshAvailability()
            return nil
        }
    }

    nonisolated private static func systemAvailability() -> CaptureIntelligenceAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case let .unavailable(reason):
                return .unavailable(message(for: reason))
            }
        }
        #endif
        return .unavailable("Apple Intelligence requires macOS 26 or later.")
    }

    nonisolated private static func systemEnhancement(
        _ input: String
    ) async throws -> CaptureEnhancement {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                throw CaptureIntelligenceError.unavailable(systemAvailability().explanation)
            }
            let session = LanguageModelSession(
                model: model,
                instructions: """
                Organize a quick note without inventing facts. Create a concise title and summary. \
                Include action items only when the note explicitly asks for work, and add at most \
                three short topical tags. Keep the person's language and meaning.
                """
            )
            let response = try await session.respond(
                to: input,
                generating: GeneratedCaptureEnhancement.self
            )
            return CaptureEnhancement(
                title: response.content.title,
                summary: response.content.summary,
                actionItems: response.content.actionItems,
                tags: response.content.tags
            )
        }
        #endif
        throw CaptureIntelligenceError.unavailable(
            "Apple Intelligence requires macOS 26 or later."
        )
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    nonisolated private static func message(
        for reason: SystemLanguageModel.Availability.UnavailableReason
    ) -> String {
        let value = String(describing: reason).lowercased()
        if value.contains("device") || value.contains("eligible") {
            return "This Mac doesn't support Apple Intelligence."
        }
        if value.contains("enabled") {
            return "Turn on Apple Intelligence in System Settings to enhance captures."
        }
        if value.contains("ready") || value.contains("download") {
            return "Apple Intelligence is still preparing its on-device model."
        }
        return "Apple Intelligence isn't available right now."
    }
    #endif
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
private struct GeneratedCaptureEnhancement {
    var title: String
    var summary: String
    var actionItems: [String]
    var tags: [String]
}
#endif
