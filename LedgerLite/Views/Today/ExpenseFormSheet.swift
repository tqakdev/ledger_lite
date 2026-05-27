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
    // C3: error alert
    @State private var showError  = false
    @State private var errorText  = ""

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
                    Button(String(localized: "Cancel")) { dismiss() }
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
                    Button(String(localized: "Done")) { focusedField = nil }
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                let vm = ExpenseFormViewModel(mode: mode, context: modelContext)
                vm.loadCategories()
                viewModel = vm
            }
            // Delay so the sheet animation settles before the keyboard appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .amount
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)  // A8
        // C3
        .alert(String(localized: "Something went wrong"), isPresented: $showError) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorText)
        }
        .onChange(of: viewModel?.errorMessage) { _, msg in
            if let msg {
                errorText = msg
                showError = true
                UINotificationFeedbackGenerator().notificationOccurred(.error)  // C1 error haptic
            }
        }
    }

    // MARK: - Form content

    @ViewBuilder
    private func formContent(_ viewModel: ExpenseFormViewModel) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // A1: redesigned amount field
                amountField(viewModel)

                if case .add = mode {
                    currencyPicker(viewModel)
                } else {
                    Text(viewModel.currencyCode)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                CategoryPickerStrip(
                    categories: viewModel.categories,
                    selected: Binding(
                        get: { viewModel.selectedCategory },
                        set: { viewModel.selectedCategory = $0 }
                    )
                )

                // A3 + A4: grouped merchant / note / date container
                detailsGroup(viewModel)
            }
            .padding(.bottom, 8)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - A1: Amount field

    private func amountField(_ viewModel: ExpenseFormViewModel) -> some View {
        let symbol = Self.currencySymbol(for: viewModel.currencyCode)
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(symbol)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .fixedSize()

            ZStack {
                // Styled placeholder — only shown when field is empty so cursor never sits on it
                if viewModel.amountString.isEmpty {
                    Text("0")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .allowsHitTesting(false)
                }
                TextField("", text: amountBinding(viewModel))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .amount)
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.15), value: viewModel.amountString)
                    // Hide cursor when empty so it doesn't overlap the styled "0" placeholder
                    .tint(viewModel.amountString.isEmpty ? .clear : .accentColor)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        // Subtle scale-in when first digit is entered
        .scaleEffect(viewModel.minorUnits > 0 ? 1.0 : 0.95)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: viewModel.minorUnits > 0)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.07), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .accessibilityLabel(String(localized: "Amount"))
        .accessibilityValue(viewModel.formattedAmount())
    }

    // A3 + A4: merchant, note, and date in a single grouped container
    private func detailsGroup(_ viewModel: ExpenseFormViewModel) -> some View {
        VStack(spacing: 0) {
            // Merchant row
            HStack(spacing: 12) {
                Image(systemName: "building.2.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                TextField(String(localized: "Merchant"), text: merchantBinding(viewModel))
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .merchant)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .note }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().padding(.leading, 16)

            // Note row
            HStack(spacing: 12) {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                TextField(String(localized: "Note"), text: noteBinding(viewModel))
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .note)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().padding(.leading, 16)

            // A4: Date row — compact picker, date only (time not surfaced in UI)
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                if let hint = dateHint(viewModel.date) {
                    Text(hint)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                DatePicker(
                    String(localized: "Date"),
                    selection: dateBinding(viewModel),
                    displayedComponents: .date
                )
                .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Currency picker

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

    // MARK: - Save

    private func save(_ viewModel: ExpenseFormViewModel) async {
        if await viewModel.save() {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()  // C1 success haptic
            onComplete()
            dismiss()
        }
    }

    // MARK: - Bindings

    private func amountBinding(_ viewModel: ExpenseFormViewModel) -> Binding<String> {
        Binding(get: { viewModel.amountString }, set: { viewModel.setAmount($0) })
    }

    private func merchantBinding(_ viewModel: ExpenseFormViewModel) -> Binding<String> {
        Binding(get: { viewModel.merchant }, set: { viewModel.merchant = $0 })
    }

    private func noteBinding(_ viewModel: ExpenseFormViewModel) -> Binding<String> {
        Binding(get: { viewModel.note }, set: { viewModel.note = $0 })
    }

    private func dateBinding(_ viewModel: ExpenseFormViewModel) -> Binding<Date> {
        Binding(get: { viewModel.date }, set: { viewModel.date = $0 })
    }

    private func currencyBinding(_ viewModel: ExpenseFormViewModel) -> Binding<String> {
        Binding(
            get: { viewModel.currencyCode },
            set: { newCode in
                if newCode != viewModel.currencyCode {
                    viewModel.currencyCode = newCode
                    viewModel.setAmount("")
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        )
    }

    // MARK: - Helpers

    private func dateHint(_ date: Date) -> String? {
        if Calendar.current.isDateInToday(date) { return String(localized: "Today") }
        if Calendar.current.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return nil
    }

    private static func currencySymbol(for code: String) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = code
        return fmt.currencySymbol ?? code
    }
}
