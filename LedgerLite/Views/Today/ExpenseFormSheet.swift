import SwiftUI
import SwiftData
import StoreKit

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

    @Environment(\.requestReview) private var requestReview
    @State private var viewModel: ExpenseFormViewModel?
    @FocusState private var focusedField: ExpenseFormField?
    @ScaledMetric(relativeTo: .largeTitle) private var amountFontSize: CGFloat = 48
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
                // Recurring template chips (add mode only)
                if case .add = mode, !viewModel.templates.isEmpty {
                    templateStrip(viewModel)
                }

                // A1: redesigned amount field
                amountField(viewModel)

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

                // A3 + A4: grouped merchant / note / date container
                detailsGroup(viewModel)
            }
            .padding(.bottom, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        // Merchant suggestion bar sits just above the keyboard
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if focusedField == .merchant, !viewModel.merchantSuggestions.isEmpty {
                merchantSuggestionBar(viewModel)
            }
        }
        .onChange(of: viewModel.merchant) { _, prefix in
            viewModel.updateMerchantSuggestions(prefix: prefix)
        }
    }

    // MARK: - Template strip

    @ViewBuilder
    private func templateStrip(_ viewModel: ExpenseFormViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                Text(String(localized: "Quick Add"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
                Spacer()
                if !viewModel.merchant.isEmpty, viewModel.minorUnits > 0, case .add = mode {
                    Button(String(localized: "Save")) {
                        viewModel.saveAsTemplate()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    .font(.caption)
                    .padding(.trailing, 16)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.templates) { template in
                        Button {
                            viewModel.applyTemplate(template)
                            focusedField = nil
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.merchantName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Text(Money(minorUnits: template.amountMinor, currencyCode: template.currencyCode).formatted())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                ExpenseTemplateService.delete(id: template.id)
                                viewModel.templates = ExpenseTemplateService.load()
                            } label: {
                                Label(String(localized: "Delete"), systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Merchant suggestion bar

    private func merchantSuggestionBar(_ viewModel: ExpenseFormViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.merchantSuggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                        viewModel.merchant = suggestion
                        viewModel.merchantSuggestions = []
                        focusedField = .note
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
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
                        .font(.system(size: amountFontSize, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .allowsHitTesting(false)
                }
                TextField("", text: amountBinding(viewModel))
                    .font(.system(size: amountFontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .amount)
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
            if case .add = mode { maybeRequestReview() }
            onComplete()
            dismiss()
        }
    }

    private func maybeRequestReview() {
        let key = "expenseSaveCount"
        let count = UserDefaults.standard.integer(forKey: key) + 1
        UserDefaults.standard.set(count, forKey: key)
        if count == 10 || count == 50 || count == 200 {
            requestReview()
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

    private static var symbolCache: [String: String] = [:]
    private static func currencySymbol(for code: String) -> String {
        if let cached = symbolCache[code] { return cached }
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = code
        let symbol = fmt.currencySymbol ?? code
        symbolCache[code] = symbol
        return symbol
    }
}
