import SwiftUI
import SwiftData

private enum SubscriptionFormField: Hashable {
    case name
    case amount
    case customDays
    case notes
}

struct SubscriptionFormSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: SubscriptionFormMode
    let onComplete: () -> Void

    @State private var viewModel: SubscriptionFormViewModel?
    @FocusState private var focusedField: SubscriptionFormField?
    @ScaledMetric(relativeTo: .largeTitle) private var amountFontSize: CGFloat = 48
    // C3
    @State private var showError = false
    @State private var errorText = ""

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
                let vm = SubscriptionFormViewModel(mode: mode, context: modelContext)
                vm.loadCategories()
                viewModel = vm
            }
            // Delay so the sheet animation settles before the keyboard appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .name
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

    @ViewBuilder
    private func formContent(_ viewModel: SubscriptionFormViewModel) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                amountSection(viewModel)
                categorySection(viewModel)
                Divider()
                detailsSection(viewModel)
            }
            .padding(.bottom, 8)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Amount section

    private func amountSection(_ viewModel: SubscriptionFormViewModel) -> some View {
        let symbol = Self.currencySymbol(for: viewModel.currencyCode)
        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(symbol)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .fixedSize()
                ZStack {
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
            .padding(.vertical, 12)
            .accessibilityLabel(String(localized: "Amount"))

            Picker(String(localized: "Currency"), selection: currencyBinding(viewModel)) {
                ForEach(Constants.App.supportedCurrencies, id: \.self) { code in
                    Text(code).tag(code)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: viewModel.currencyCode) { _, _ in
                focusedField = .amount
            }
        }
    }

    // MARK: - Category section

    private func categorySection(_ viewModel: SubscriptionFormViewModel) -> some View {
        CategoryPickerStrip(
            categories: viewModel.categories,
            selected: Binding(
                get: { viewModel.selectedCategory },
                set: { viewModel.selectedCategory = $0 }
            )
        )
    }

    // MARK: - Details section

    @ViewBuilder
    private func detailsSection(_ viewModel: SubscriptionFormViewModel) -> some View {
        VStack(spacing: 12) {
            // Name — grouped card matching ExpenseFormSheet.detailsGroup style
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "tag")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    TextField(String(localized: "Name"), text: nameBinding(viewModel))
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .amount }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            billingCycleSection(viewModel)

            DatePicker(
                String(localized: "Next Billing Date"),
                selection: nextDateBinding(viewModel),
                displayedComponents: .date
            )
            .padding(.horizontal)

            // Notes — grouped card
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "note.text")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    TextField(String(localized: "Notes (optional)"), text: notesBinding(viewModel))
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .notes)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            if case .edit(let sub) = mode {
                statusActionsSection(viewModel, subscription: sub)
            }
        }
    }

    // MARK: - Billing cycle

    @ViewBuilder
    private func billingCycleSection(_ viewModel: SubscriptionFormViewModel) -> some View {
        VStack(spacing: 8) {
            Picker(String(localized: "Billing Cycle"), selection: Binding(
                get: { viewModel.billingCycle },
                set: { viewModel.billingCycle = $0 }
            )) {
                Text(String(localized: "Weekly")).tag(BillingCycle.weekly)
                Text(String(localized: "Monthly")).tag(BillingCycle.monthly)
                Text(String(localized: "Yearly")).tag(BillingCycle.yearly)
                Text(String(localized: "Custom")).tag(BillingCycle.customDays(30))
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if case .customDays = viewModel.billingCycle {
                HStack {
                    Text(String(localized: "Every"))
                        .foregroundStyle(.secondary)
                    TextField("30", text: Binding(
                        get: { viewModel.customDays },
                        set: { viewModel.customDays = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .customDays)
                    .frame(width: 72)
                    Text(String(localized: "days"))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Status actions (edit mode only)

    @ViewBuilder
    private func statusActionsSection(_ viewModel: SubscriptionFormViewModel, subscription: Subscription) -> some View {
        VStack(spacing: 8) {
            Divider().padding(.top, 4)

            switch subscription.status {
            case .active:
                Button(String(localized: "Pause Subscription")) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()  // C1
                    subscription.status = .paused
                    try? modelContext.save()
                    onComplete()
                    dismiss()
                }
                .foregroundStyle(.orange)

            case .paused:
                Button(String(localized: "Resume Subscription")) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()  // C1
                    subscription.status = .active
                    try? modelContext.save()
                    onComplete()
                    dismiss()
                }
                .foregroundStyle(.green)

            case .cancelled:
                EmptyView()
            }

            if subscription.status != .cancelled {
                Button(String(localized: "Cancel Subscription"), role: .destructive) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()  // C1
                    subscription.status = .cancelled
                    try? modelContext.save()
                    onComplete()
                    dismiss()
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    // MARK: - Save

    private func save(_ viewModel: SubscriptionFormViewModel) async {
        if await viewModel.save() {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()  // C1 success haptic
            onComplete()
            dismiss()
        }
    }

    // MARK: - Helpers

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

    // MARK: - Bindings

    private func amountBinding(_ viewModel: SubscriptionFormViewModel) -> Binding<String> {
        Binding(get: { viewModel.amountString }, set: { viewModel.setAmount($0) })
    }

    private func currencyBinding(_ viewModel: SubscriptionFormViewModel) -> Binding<String> {
        Binding(
            get: { viewModel.currencyCode },
            set: { newCode in
                if newCode != viewModel.currencyCode {
                    viewModel.setCurrency(newCode)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        )
    }

    private func nameBinding(_ viewModel: SubscriptionFormViewModel) -> Binding<String> {
        Binding(get: { viewModel.name }, set: { viewModel.name = $0 })
    }

    private func notesBinding(_ viewModel: SubscriptionFormViewModel) -> Binding<String> {
        Binding(get: { viewModel.notes }, set: { viewModel.notes = $0 })
    }

    private func nextDateBinding(_ viewModel: SubscriptionFormViewModel) -> Binding<Date> {
        Binding(get: { viewModel.nextBillingDate }, set: { viewModel.nextBillingDate = $0 })
    }
}
