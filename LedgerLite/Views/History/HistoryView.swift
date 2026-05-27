import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: HistoryViewModel?
    @State private var showError = false
    @State private var errorText = ""

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    content(vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(String(localized: "History"))
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            if viewModel == nil {
                viewModel = HistoryViewModel(context: modelContext)
            }
            viewModel?.refresh()
        }
        .alert(String(localized: "Something went wrong"), isPresented: $showError) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorText)
        }
        .onChange(of: viewModel?.errorMessage) { _, msg in
            if let msg {
                errorText = msg
                showError = true
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    // MARK: - Content

    private func content(_ vm: HistoryViewModel) -> some View {
        VStack(spacing: 0) {
            dateNavBar(vm)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            Divider()
            if vm.isLoading && vm.expenses.isEmpty {
                ProgressView().frame(maxHeight: .infinity)
            } else if vm.filteredExpenses.isEmpty {
                emptyState(vm).frame(maxHeight: .infinity)
            } else {
                expenseList(vm)
            }
        }
        .searchable(
            text: Binding(get: { vm.searchText }, set: { vm.searchText = $0 }),
            prompt: String(localized: "Search expenses")
        )
        .sheet(item: sheetBinding(vm)) { sheet in
            ExpenseFormSheet(mode: sheet.formMode) { vm.dismissSheet() }
        }
    }

    // MARK: - Date navigation bar

    private func dateNavBar(_ vm: HistoryViewModel) -> some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                vm.previousDay()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            Spacer()
            VStack(spacing: 2) {
                Text(dateHeading(vm.selectedDate))
                    .font(.headline)
                if !Calendar.current.isDateInToday(vm.selectedDate) &&
                   !Calendar.current.isDateInYesterday(vm.selectedDate) {
                    Text(vm.selectedDate.formatted(.dateTime.year()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                vm.nextDay()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .disabled(vm.isToday)
            .opacity(vm.isToday ? 0.3 : 1.0)
        }
    }

    private func dateHeading(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return String(localized: "Today") }
        if Calendar.current.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return date.formatted(.dateTime.month(.wide).day())
    }

    // MARK: - Summary card

    private func summaryCard(_ vm: HistoryViewModel) -> some View {
        let count = vm.filteredExpenses.count
        let label = count == 1
            ? String(localized: "1 expense")
            : String(localized: "\(count) expenses")
        return VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Day Total"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(vm.dayTotalFormatted)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.10), Color(.secondarySystemGroupedBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Expense list

    private func expenseList(_ vm: HistoryViewModel) -> some View {
        VStack(spacing: 0) {
            summaryCard(vm)
                .padding(.horizontal)
                .padding(.vertical, 8)
            List {
                Section {
                    ForEach(vm.filteredExpenses, id: \.id) { expense in
                        ExpenseRowView(
                            expense: expense,
                            homeCurrencyCode: vm.homeCurrencyCode
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { vm.presentEdit(for: expense) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                vm.deleteExpense(expense)
                            } label: {
                                Label(String(localized: "Delete"), systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                vm.presentEdit(for: expense)
                            } label: {
                                Label(String(localized: "Edit"), systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Empty state

    private func emptyState(_ vm: HistoryViewModel) -> some View {
        ContentUnavailableView {
            Label(
                vm.searchText.isEmpty
                    ? String(localized: "No Expenses")
                    : String(localized: "No Results"),
                systemImage: vm.searchText.isEmpty ? "calendar.badge.minus" : "magnifyingglass"
            )
        } description: {
            Text(vm.searchText.isEmpty
                 ? String(localized: "No expenses recorded for this day.")
                 : String(localized: "No expenses match your search."))
        }
    }

    // MARK: - Helpers

    private func sheetBinding(_ vm: HistoryViewModel) -> Binding<HistorySheet?> {
        Binding(
            get: { vm.activeSheet },
            set: { vm.activeSheet = $0 }
        )
    }
}

#if DEBUG
#Preview {
    HistoryView()
        .modelContainer(PreviewContainer.shared)
}
#endif
