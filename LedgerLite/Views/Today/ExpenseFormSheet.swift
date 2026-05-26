import SwiftUI
import SwiftData

private enum ExpenseFormField: Hashable {
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

    private var isEnteringAmount: Bool { focusedField == nil }

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
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func formContent(_ viewModel: ExpenseFormViewModel) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                amountHeader(viewModel)

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

                if !isEnteringAmount {
                    // Spacer so last field can scroll above the keyboard.
                    Color.clear.frame(height: 8)
                }
            }
            .padding(.bottom, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isEnteringAmount {
                AmountNumpad(
                    decimalPlaces: viewModel.decimalPlaces,
                    onDigit: { viewModel.appendDigit($0) },
                    onDelete: { viewModel.deleteLastDigit() }
                )
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(.bar)
            }
        }
    }

    private func amountHeader(_ viewModel: ExpenseFormViewModel) -> some View {
        Button {
            focusedField = nil
        } label: {
            VStack(spacing: 4) {
                Text(viewModel.formattedAmount())
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                if !isEnteringAmount {
                    Text(String(localized: "Tap amount to use keypad"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Amount"))
        .accessibilityValue(viewModel.formattedAmount())
        .accessibilityHint(String(localized: "Shows the number pad for entering the amount"))
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
            focusedField = nil
        }
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
                    withAnimation(.default) { viewModel.minorUnits = 0 }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        )
    }
}
