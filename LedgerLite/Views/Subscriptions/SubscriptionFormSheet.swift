import SwiftUI
import SwiftData

private enum SubscriptionFormField: Hashable {
    case name
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
            // Start on the amount numpad (focusedField == nil), not the name keyboard.
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
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if focusedField == nil {
                AmountNumpad(
                    separator: separator,
                    allowsDecimal: Money.decimals(for: viewModel.currencyCode) > 0,
                    onDigit: { numpadDigit($0, viewModel) },
                    onSeparator: { numpadSeparator(viewModel) },
                    onBackspace: { numpadBackspace(viewModel) }
                )
            }
        }
    }

    // MARK: - Amount section

    private func amountSection(_ viewModel: SubscriptionFormViewModel) -> some View {
        let symbol = Money.symbol(for: viewModel.currencyCode)
        let isEmpty = viewModel.amountString.isEmpty
        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(symbol)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
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
            .animation(.spring(duration: 0.3, bounce: 0.5), value: viewModel.minorUnits > 0)
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
            .accessibilityValue(Money(minorUnits: viewModel.minorUnits, currencyCode: viewModel.currencyCode).formatted())

            Picker(String(localized: "Currency"), selection: currencyBinding(viewModel)) {
                ForEach(Constants.App.supportedCurrencies, id: \.self) { code in
                    Text(code).tag(code)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: viewModel.currencyCode) { _, _ in
                focusedField = nil
            }
        }
    }

    // MARK: - Category section

    private func categorySection(_ viewModel: SubscriptionFormViewModel) -> some View {
        @Bindable var vm = viewModel
        return CategoryPickerStrip(categories: vm.categories, selected: $vm.selectedCategory)
    }

    // MARK: - Details section

    @ViewBuilder
    private func detailsSection(_ viewModel: SubscriptionFormViewModel) -> some View {
        @Bindable var vm = viewModel
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "tag")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    TextField(String(localized: "Name"), text: $vm.name)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            billingCycleSection(vm)

            DatePicker(
                String(localized: "Next Billing Date"),
                selection: $vm.nextBillingDate,
                displayedComponents: .date
            )
            .padding(.horizontal)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "note.text")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    TextField(String(localized: "Notes (optional)"), text: $vm.notes)
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
        @Bindable var vm = viewModel
        VStack(spacing: 8) {
            Picker(String(localized: "Billing Cycle"), selection: $vm.billingCycle) {
                Text(String(localized: "Weekly")).tag(BillingCycle.weekly)
                Text(String(localized: "Monthly")).tag(BillingCycle.monthly)
                Text(String(localized: "Yearly")).tag(BillingCycle.yearly)
                Text(String(localized: "Custom")).tag(BillingCycle.customDays(30))
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if case .customDays = vm.billingCycle {
                HStack {
                    Text(String(localized: "Every"))
                        .foregroundStyle(.secondary)
                    TextField("30", text: $vm.customDays)
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
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    subscription.status = .paused
                    try? modelContext.save()
                    onComplete()
                    dismiss()
                }
                .foregroundStyle(Theme.caution)

            case .paused:
                Button(String(localized: "Resume Subscription")) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    subscription.status = .active
                    try? modelContext.save()
                    onComplete()
                    dismiss()
                }
                .foregroundStyle(Theme.positive)

            case .cancelled:
                EmptyView()
            }

            if subscription.status != .cancelled {
                Button(String(localized: "Cancel Subscription"), role: .destructive) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onComplete()
            dismiss()
        }
    }

    // MARK: - Helpers

    // MARK: - Numpad input

    private var separator: String { Locale.current.decimalSeparator ?? "." }

    private func numpadDigit(_ digit: String, _ vm: SubscriptionFormViewModel) {
        vm.setAmount(vm.amountString + digit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func numpadSeparator(_ vm: SubscriptionFormViewModel) {
        guard !vm.amountString.contains(separator) else { return }
        vm.setAmount((vm.amountString.isEmpty ? "0" : vm.amountString) + separator)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func numpadBackspace(_ vm: SubscriptionFormViewModel) {
        guard !vm.amountString.isEmpty else { return }
        vm.setAmount(String(vm.amountString.dropLast()))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Bindings

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

}
