import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: TodayViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    todayContent(viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(String(localized: "Today"))
        }
        .overlay(alignment: .bottomTrailing) {
            if let viewModel {
                quickAddFAB(viewModel)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = TodayViewModel(context: modelContext)
            }
            viewModel?.refresh()
        }
        .sheet(item: sheetBinding) { sheet in
            ExpenseFormSheet(mode: sheet.formMode) {
                viewModel?.dismissSheet()
            }
        }
    }

    @ViewBuilder
    private func todayContent(_ viewModel: TodayViewModel) -> some View {
        if viewModel.expenses.isEmpty {
            emptyState
        } else {
            List {
                Section {
                    todaySummary(viewModel)
                }
                Section(String(localized: "Expenses")) {
                    ForEach(viewModel.expenses, id: \.id) { expense in
                        ExpenseRowView(
                            expense: expense,
                            homeCurrencyCode: viewModel.homeCurrencyCode
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.presentEdit(for: expense)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.deleteExpense(expense)
                            } label: {
                                Label(String(localized: "Delete"), systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                viewModel.presentEdit(for: expense)
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

        if let error = viewModel.errorMessage {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .padding()
        }
    }

    private func todaySummary(_ viewModel: TodayViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Today's Total"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(viewModel.todayTotalFormatted)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
            Text(Date.now.formatted(date: .complete, time: .omitted))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func quickAddFAB(_ viewModel: TodayViewModel) -> some View {
        Button {
            viewModel.presentQuickAdd()
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
        .accessibilityLabel(String(localized: "Quick Add"))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "No Expenses Today"), systemImage: "tray")
        } description: {
            Text(String(localized: "Tap + to log your first expense."))
        } actions: {
            Button(String(localized: "Quick Add")) {
                viewModel?.presentQuickAdd()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var sheetBinding: Binding<TodaySheet?> {
        Binding(
            get: { viewModel?.activeSheet },
            set: { viewModel?.activeSheet = $0 }
        )
    }
}

#if DEBUG
#Preview {
    TodayView()
        .modelContainer(PreviewContainer.shared)
}
#endif
