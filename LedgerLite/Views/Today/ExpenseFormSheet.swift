import SwiftUI
import SwiftData

private enum ExpenseFormField: Hashable {
    case amount
    case merchant
    case note
}

struct ExpenseFormSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: ExpenseFormMode
    let onComplete: () -> Void

    @State private var viewModel: ExpenseFormViewModel?
    @FocusState private var focusedField: ExpenseFormField?

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
                            focusedField = nil
                            Task { await save(viewModel) }
                        }
                        .fontWeight(.semibold)
                        .disabled(!viewModel.canSave)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(String(localized: "Done")) {
                        focusedField = nil
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
            focusedField = .amount
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func formContent(_ viewModel: ExpenseFormViewModel) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                amountField(viewModel)

                if case .add = mode {
                    // Currency is intentionally hidden in edit mode — changing it after creation
                    // would require re-fetching the exchange rate and recalculating the home-currency amount.
                    currencyPicker(viewModel)
                }

                CategoryPickerStrip(
                    categories: viewModel.categories,
                    selected: Binding(
                        get: { viewModel.selectedCategory },
                        set: { viewModel.selectedCategory = $0 }
                    )
                )

                Divider()

                VStack(spacing: 8) {
                    TextField(String(localized: "Merchant"), text: merchantBinding(viewModel))
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .merchant)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .note }

                    TextField(String(localized: "Note"), text: noteBinding(viewModel))
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .note)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                }
                .padding(.horizontal)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.bottom, 8)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func amountField(_ viewModel: ExpenseFormViewModel) -> some View {
        TextField("0", text: amountBinding(viewModel))
            .font(.system(size: 40, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .keyboardType(.decimalPad)
            .focused($focusedField, equals: .amount)
            .padding(.vertical, 12)
            .accessibilityLabel(String(localized: "Amount"))
            .accessibilityValue(viewModel.formattedAmount())
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
        .onChange(of: viewModel.currencyCode) { _, _ in
            focusedField = .amount
        }
    }

    private func save(_ viewModel: ExpenseFormViewModel) async {
        if await viewModel.save() {
            onComplete()
            dismiss()
        }
    }

    private func amountBinding(_ viewModel: ExpenseFormViewModel) -> Binding<String> {
        Binding(
            get: { viewModel.amountString },
            set: { viewModel.setAmount($0) }
        )
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
                    // Currency change resets the amount — different currencies have different
                    // minor-unit scales (JPY vs USD) so keeping the number would be misleading.
                    viewModel.currencyCode = newCode
                    viewModel.setAmount("")
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        )
    }
}
