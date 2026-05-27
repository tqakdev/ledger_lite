import Foundation
import SwiftData

@MainActor
@Observable
final class AutoDetectViewModel {

    // MARK: - Inputs / outputs

    var rawText: String = ""
    var candidates: [SubscriptionCandidate] = []
    var categories: [Category] = []
    var isSaving: Bool = false
    var errorMessage: String?
    var hasConfirmedAtLeastOne: Bool = false

    /// Set by the scene delegate when a Share Extension payload arrives.
    /// Setting this automatically triggers detection.
    var shareExtensionText: String? {
        didSet {
            guard let text = shareExtensionText, !text.isEmpty else { return }
            rawText = text
            runDetection()
        }
    }

    // MARK: - Dependencies

    private let subscriptionRepository: SubscriptionRepository
    private let categoryRepository: CategoryRepository
    private let subscriptionService: SubscriptionService

    // MARK: - Init

    init(context: ModelContext) {
        self.subscriptionRepository = SubscriptionRepository(context: context)
        self.categoryRepository     = CategoryRepository(context: context)
        self.subscriptionService    = SubscriptionService(context: context)
    }

    // MARK: - Setup

    func loadCategories() {
        categories = (try? categoryRepository.fetchAll()) ?? []
    }

    // MARK: - Detection

    func runDetection() {
        hasConfirmedAtLeastOne = false
        let detected = SubscriptionDetector.detect(in: rawText)
        let existingNames = Set(
            ((try? subscriptionRepository.fetchAll()) ?? []).map { $0.name.lowercased() }
        )
        candidates = detected.map { candidate in
            var marked = candidate
            marked.isDuplicate = existingNames.contains(candidate.name.lowercased())
            return marked
        }
        AppLogger.subscriptions.info("Auto-detection found \(self.candidates.count) candidate(s)")
    }

    // MARK: - Confirmation

    func confirm(_ candidate: SubscriptionCandidate, category: Category?, nextBillingDate: Date? = nil) async {
        let nextDate = nextBillingDate
            ?? candidate.detectedNextBillingDate
            ?? candidate.billingCycle.nextDate(after: Date.utcToday)
        let sub = Subscription(
            name: candidate.name,
            amountMinor: candidate.amountMinor,
            currencyCode: candidate.currencyCode,
            billingCycle: candidate.billingCycle,
            nextBillingDate: nextDate
        )
        sub.category = category

        do {
            try subscriptionRepository.add(sub)
            await subscriptionService.scheduleNotification(for: sub)
            dismiss(candidate)
            hasConfirmedAtLeastOne = true
            AppLogger.subscriptions.info("Confirmed auto-detected subscription: \(sub.name)")
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.subscriptions.error("Auto-detect confirm failed: \(error)")
        }
    }

    func dismiss(_ candidate: SubscriptionCandidate) {
        candidates.removeAll { $0.id == candidate.id }
    }

    func confirmAll() async {
        isSaving = true
        defer { isSaving = false }
        let toConfirm = candidates.filter { !$0.isDuplicate }
        for candidate in toConfirm {
            await confirm(candidate, category: nil)
        }
    }
}
