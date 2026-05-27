import Foundation
import SwiftData

@MainActor
@Observable
final class InsightsViewModel {

    // MARK: - Period

    enum Period: String, CaseIterable, Identifiable {
        case week = "week"
        case month = "month"
        case year = "year"
        case allTime = "allTime"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .week:    return String(localized: "This Week")
            case .month:   return String(localized: "This Month")
            case .year:    return String(localized: "This Year")
            case .allTime: return String(localized: "All Time")
            }
        }

        // Compact label used inside the segmented picker — fits 4 segments on SE (375pt).
        var shortName: String {
            switch self {
            case .week:    return String(localized: "Week")
            case .month:   return String(localized: "Month")
            case .year:    return String(localized: "Year")
            case .allTime: return String(localized: "All Time")
            }
        }
    }

    // MARK: - Outputs

    var period: Period = .month
    var categoryTotals: [(category: Category, minorUnits: Int)] = []
    var dailyTotals: [(date: Date, minorUnits: Int)] = []
    var periodTotalMinor: Int = 0
    var selectedCategory: Category? = nil
    var homeCurrencyCode: String = UserPreferences.homeCurrencyCode
    var allCategories: [Category] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var topMerchant: (merchant: String, minorUnits: Int)? = nil
    var periodExpenses: [Expense] = []

    // MARK: - Dependencies

    private let expenseRepository: ExpenseRepository
    private let categoryRepository: CategoryRepository

    // MARK: - Init

    init(context: ModelContext) {
        expenseRepository  = ExpenseRepository(context: context)
        categoryRepository = CategoryRepository(context: context)
    }

    // MARK: - Refresh

    func refresh() async {
        await refresh(referenceDate: Date())
    }

    func refresh(referenceDate: Date) async {
        isLoading = true
        defer { isLoading = false }

        homeCurrencyCode = UserPreferences.homeCurrencyCode
        errorMessage = nil

        do {
            allCategories = (try? categoryRepository.fetchAll()) ?? []
            let all       = try expenseRepository.fetchAll()
            let filtered  = filter(all, period: period, referenceDate: referenceDate)
            periodExpenses   = filtered
            categoryTotals   = makeCategoryTotals(filtered)
            dailyTotals      = makeGroupedTotals(filtered, period: period)
            periodTotalMinor = makePeriodTotal(filtered)
            topMerchant      = makeTopMerchant(filtered)
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.data.error("InsightsViewModel refresh failed: \(error)")
        }
    }

    // MARK: - Period filtering (internal for testing)

    func filter(_ expenses: [Expense], period: Period, referenceDate: Date) -> [Expense] {
        let cal = Calendar.current
        switch period {
        case .week:
            let weekday   = cal.component(.weekday, from: referenceDate)
            let offset    = (weekday - cal.firstWeekday + 7) % 7
            let weekStart = cal.startOfDay(for: cal.date(byAdding: .day, value: -offset, to: referenceDate)!)
            return expenses.filter { $0.date >= weekStart }
        case .month:
            var comps  = cal.dateComponents([.year, .month], from: referenceDate)
            comps.day  = 1
            let start  = cal.date(from: comps)!
            return expenses.filter { $0.date >= start }
        case .year:
            var comps  = cal.dateComponents([.year], from: referenceDate)
            comps.month = 1; comps.day = 1
            let start   = cal.date(from: comps)!
            return expenses.filter { $0.date >= start }
        case .allTime:
            return expenses
        }
    }

    // MARK: - Aggregation

    private func makeCategoryTotals(_ expenses: [Expense]) -> [(category: Category, minorUnits: Int)] {
        var groups: [ObjectIdentifier: (category: Category, sum: Decimal)] = [:]
        for e in expenses {
            guard let cat = e.category else { continue }
            let key = ObjectIdentifier(cat)
            let v   = homeDecimal(e)
            if var entry = groups[key] { entry.sum += v; groups[key] = entry }
            else { groups[key] = (cat, v) }
        }
        let places = Money.decimals(for: homeCurrencyCode)
        return groups.values
            .map { (category: $0.category, minorUnits: toMinor($0.sum, places: places)) }
            .sorted { $0.minorUnits > $1.minorUnits }
    }

    private func makeGroupedTotals(_ expenses: [Expense], period: Period) -> [(date: Date, minorUnits: Int)] {
        let cal     = Calendar.current
        let byMonth = period == .year || period == .allTime
        var groups: [Date: Decimal] = [:]
        for e in expenses {
            let bucket: Date
            if byMonth {
                var comps = cal.dateComponents([.year, .month], from: e.date)
                comps.day = 1
                bucket = cal.date(from: comps) ?? cal.startOfDay(for: e.date)
            } else {
                bucket = cal.startOfDay(for: e.date)
            }
            groups[bucket, default: 0] += homeDecimal(e)
        }
        let places = Money.decimals(for: homeCurrencyCode)
        return groups
            .map { (date: $0.key, minorUnits: toMinor($0.value, places: places)) }
            .sorted { $0.date < $1.date }
    }

    private func makePeriodTotal(_ expenses: [Expense]) -> Int {
        let sum = expenses.reduce(Decimal(0)) { $0 + homeDecimal($1) }
        return toMinor(sum, places: Money.decimals(for: homeCurrencyCode))
    }

    // MARK: - Helpers

    private func homeDecimal(_ expense: Expense) -> Decimal {
        expense.money.decimalValue * expense.exchangeRateToHome
    }

    private func toMinor(_ d: Decimal, places: Int) -> Int {
        let rounded = d.rounded(scale: places)
        let minor   = (rounded * Decimal.powerOfTen(places)).rounded(scale: 0)
        return (minor as NSDecimalNumber).intValue
    }

    private func makeTopMerchant(_ expenses: [Expense]) -> (merchant: String, minorUnits: Int)? {
        var groups: [String: Decimal] = [:]
        for e in expenses {
            guard let m = e.merchant, !m.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            groups[m, default: 0] += homeDecimal(e)
        }
        guard !groups.isEmpty else { return nil }
        let places = Money.decimals(for: homeCurrencyCode)
        return groups
            .map { (merchant: $0.key, minorUnits: toMinor($0.value, places: places)) }
            .max(by: { $0.minorUnits < $1.minorUnits })
    }
}
