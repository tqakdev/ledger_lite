import SwiftUI
import SwiftData

struct ExpenseFormSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: ExpenseFormMode
    let onComplete: () -> Void

    @State private var viewModel: ExpenseFormViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    formContent(viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let viewModel {
                        Button(String(localized: "Save")) {
                            Task { await save(viewModel) }
                        }
                        .fontWeight(.semibold)
                        .disabled(!viewModel.canSave)
                    }
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                let vm = ExpenseFormViewModel(mode: mode, context: modelContext)
                vm.loadCategories()
                viewModel = vm
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func formContent(_ viewModel: ExpenseFormViewModel) -> some View {
        VStack(spacing: 0) {
            Text(viewModel.formattedAmount())
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .accessibilityLabel(String(localized: "Amount"))
                .accessibilityValue(viewModel.formattedAmount())

            if case .add = mode {
                currencyPicker(viewModel)
            }

            CategoryPickerStrip(
                categories: viewModel.categories,
                selected: Binding(
                    get: { viewModel.selectedCategory },
                    set: { viewModel.selectedCategory = $0 }
                )
            )
            .padding(.vertical, 12)

            VStack(spacing: 8) {
                TextField(String(localized: "Merchant"), text: merchantBinding(viewModel))
                    .textFieldStyle(.roundedBorder)
                TextField(String(localized: "Note"), text: noteBinding(viewModel))
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)

            Spacer(minLength: 12)

            AmountNumpad(
                decimalPlaces: viewModel.decimalPlaces,
                onDigit: { viewModel.appendDigit($0) },
                onDelete: { viewModel.deleteLastDigit() }
            )
            .padding(.horizontal)
            .padding(.bottom, 8)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private func currencyPicker(_ viewModel: ExpenseFormViewModel) -> some View {
        Picker(String(localized: "Currency"), selection: currencyBinding(viewModel)) {
            ForEach(Constants.App.supportedCurrencies, id: \.self) { code in
                Text(code).tag(code)
            }
        }
        .pickerStyle(.menu)
        .padding(.horizontal)
    }

    private func save(_ viewModel: ExpenseFormViewModel) async {
        if await viewModel.save() {
            onComplete()
            dismiss()
        }
    }

    private func merchantBinding(_ viewModel: ExpenseFormViewModel) -> Binding<String> {
        Binding(
            get: { viewModel.merchant },
            set: { viewModel.merchant = $0 }
        )
    }

    private func noteBinding(_ viewModel: ExpenseFormViewModel) -> Binding<String> {
        Binding(
            get: { viewModel.note },
            set: { viewModel.note = $0 }
        )
    }

    private func currencyBinding(_ viewModel: ExpenseFormViewModel) -> Binding<String> {
        Binding(
            get: { viewModel.currencyCode },
            set: { newCode in
                if newCode != viewModel.currencyCode {
                    viewModel.currencyCode = newCode
                    viewModel.minorUnits = 0
                }
            }
        )
    }
}
