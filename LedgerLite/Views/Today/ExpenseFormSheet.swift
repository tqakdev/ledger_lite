import SwiftUI
import SwiftData
import StoreKit

private enum ExpenseFormField: Hashable {
    case merchant
    case note
}

struct ExpenseFormSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: ExpenseFormMode
    var autoScan: Bool = false
    let onComplete: () -> Void

    @Environment(\.requestReview) private var requestReview
    @State private var viewModel: ExpenseFormViewModel?
    @FocusState private var focusedField: ExpenseFormField?
    @ScaledMetric(relativeTo: .largeTitle) private var amountFontSize: CGFloat = 48
    @State private var detailsExpanded = false
    @State private var showScanner = false
    @State private var didAutoScan = false
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
            // In edit mode the details usually already hold a merchant/note, so reveal them.
            if case .edit = mode { detailsExpanded = true }
            // Camera-FAB entry opens straight into the scanner.
            if autoScan && !didAutoScan {
                didAutoScan = true
                showScanner = true
            }
        }
        .sheet(isPresented: $showScanner) {
            ReceiptScanView(
                defaultCurrency: viewModel?.currencyCode ?? UserPreferences.homeCurrencyCode
            ) { receipt in
                showScanner = false
                guard !receipt.isEmpty else { return }
                viewModel?.applyParsedReceipt(receipt)
                if let vm = viewModel, vm.merchant.isEmpty == false || vm.note.isEmpty == false {
                    detailsExpanded = true
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } onCancel: {
                showScanner = false
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
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

    // MARK: - Form content

    @ViewBuilder
    private func formContent(_ viewModel: ExpenseFormViewModel) -> some View {
        @Bindable var vm = viewModel
        ScrollView {
            VStack(spacing: 16) {
                if case .add = mode, !vm.templates.isEmpty {
                    templateStrip(vm)
                }

                if case .add = mode {
                    scanReceiptButton
                }

                amountDisplay(vm)

                if vm.scanLowConfidence {
                    Label(String(localized: "Scanned — double-check the amount."), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                if case .add = mode {
                    currencyPicker(vm)
                }

                CategoryPickerStrip(
                    categories: vm.categories,
                    selected: $vm.selectedCategory
                )

                detailsDisclosure(vm)
            }
            .padding(.bottom, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar(vm)
        }
        .onChange(of: vm.merchant) { _, prefix in
            vm.updateMerchantSuggestions(prefix: prefix)
        }
    }

    // MARK: - Scan receipt button

    private var scanReceiptButton: some View {
        Button {
            focusedField = nil
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showScanner = true
        } label: {
            Label(String(localized: "Scan a receipt"), systemImage: "doc.text.viewfinder")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal)
    }

    // MARK: - Bottom bar (numpad / merchant suggestions)

    @ViewBuilder
    private func bottomBar(_ viewModel: ExpenseFormViewModel) -> some View {
        if focusedField == .merchant, !viewModel.merchantSuggestions.isEmpty {
            merchantSuggestionBar(viewModel)
        } else if focusedField == nil {
            AmountNumpad(
                separator: separator,
                allowsDecimal: Money.decimals(for: viewModel.currencyCode) > 0,
                canSave: viewModel.canSave,
                saveTitle: saveButtonTitle,
                onDigit: { numpadDigit($0, viewModel) },
                onSeparator: { numpadSeparator(viewModel) },
                onBackspace: { numpadBackspace(viewModel) },
                onSave: { Task { await save(viewModel) } }
            )
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

    // MARK: - Amount display

    private func amountDisplay(_ viewModel: ExpenseFormViewModel) -> some View {
        let symbol = Money.symbol(for: viewModel.currencyCode)
        let isEmpty = viewModel.amountString.isEmpty
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(symbol)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .fixedSize()

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(isEmpty ? "0" : viewModel.amountString)
                    .font(.system(size: amountFontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isEmpty ? .tertiary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)

                BlinkingCaret(height: amountFontSize * 0.62)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
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
        .contentShape(Rectangle())
        .onTapGesture { focusedField = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Amount"))
        .accessibilityValue(viewModel.formattedAmount())
    }

    // MARK: - Details (collapsible)

    @ViewBuilder
    private func detailsDisclosure(_ viewModel: ExpenseFormViewModel) -> some View {
        @Bindable var vm = viewModel
        VStack(spacing: 0) {
            Button {
                focusedField = nil
                withAnimation(.easeInOut(duration: 0.2)) { detailsExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(collapsedSummary(vm))
                        .font(.subheadline)
                        .foregroundStyle(!detailsExpanded && detailsHaveContent(vm) ? .primary : .secondary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: detailsExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if detailsExpanded {
                Divider().padding(.leading, 16)

                HStack(spacing: 12) {
                    Image(systemName: "building.2.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    TextField(String(localized: "Merchant"), text: $vm.merchant)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .merchant)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .note }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().padding(.leading, 16)

                HStack(spacing: 12) {
                    Image(systemName: "note.text")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    TextField(String(localized: "Note"), text: $vm.note, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...8)
                        .focused($focusedField, equals: .note)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().padding(.leading, 16)

                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    if let hint = dateHint(vm.date) {
                        Text(hint)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    DatePicker(
                        String(localized: "Date"),
                        selection: $vm.date,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func detailsHaveContent(_ vm: ExpenseFormViewModel) -> Bool {
        !vm.merchant.isEmpty || !vm.note.isEmpty
    }

    private func collapsedSummary(_ vm: ExpenseFormViewModel) -> String {
        if detailsExpanded { return String(localized: "Details") }
        if !vm.merchant.isEmpty { return vm.merchant }
        if !vm.note.isEmpty { return vm.note }
        return String(localized: "Add merchant, note, date")
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
            focusedField = nil
        }
    }

    // MARK: - Numpad input

    private var separator: String { Locale.current.decimalSeparator ?? "." }

    private func numpadDigit(_ digit: String, _ vm: ExpenseFormViewModel) {
        vm.setAmount(vm.amountString + digit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func numpadSeparator(_ vm: ExpenseFormViewModel) {
        guard !vm.amountString.contains(separator) else { return }
        vm.setAmount((vm.amountString.isEmpty ? "0" : vm.amountString) + separator)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func numpadBackspace(_ vm: ExpenseFormViewModel) {
        guard !vm.amountString.isEmpty else { return }
        vm.setAmount(String(vm.amountString.dropLast()))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private var saveButtonTitle: String {
        if case .edit = mode { return String(localized: "Save Changes") }
        return String(localized: "Add Expense")
    }

    // MARK: - Save

    private func save(_ viewModel: ExpenseFormViewModel) async {
        focusedField = nil
        if await viewModel.save() {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
}
