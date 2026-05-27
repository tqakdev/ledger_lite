import SwiftUI
import SwiftData

struct SubscriptionsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: SubscriptionsViewModel?
    @State private var inactiveSectionExpanded = false
    @State private var showError = false
    @State private var errorText = ""

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    subscriptionsContent(viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(String(localized: "Subscriptions"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if let viewModel {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            viewModel.presentAdd()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                        .accessibilityLabel(String(localized: "Add Subscription"))
                    }
                    ToolbarItem(placement: .secondaryAction) {
                        Button {
                            viewModel.presentAutoDetect()
                        } label: {
                            Label(String(localized: "Scan"), systemImage: "doc.text.magnifyingglass")
                        }
                    }
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = SubscriptionsViewModel(context: modelContext)
            }
            viewModel?.refresh()
        }
        .sheet(item: destinationBinding) { destination in
            switch destination {
            case .add:
                SubscriptionFormSheet(mode: .add) { viewModel?.dismissDestination() }
            case .edit(let sub):
                SubscriptionFormSheet(mode: .edit(sub)) { viewModel?.dismissDestination() }
            case .autoDetect:
                AutoDetectSheet()
                    .onDisappear { viewModel?.dismissDestination() }
            }
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

    @ViewBuilder
    private func subscriptionsContent(_ viewModel: SubscriptionsViewModel) -> some View {
        if viewModel.subscriptions.isEmpty {
            emptyState(viewModel)
        } else {
            List {
                Section {
                    monthlyCostCard(viewModel)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section(String(localized: "Active (\(viewModel.activeSubscriptions.count))")) {
                    if viewModel.activeSubscriptions.isEmpty {
                        Text(String(localized: "No active subscriptions"))
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(viewModel.activeSubscriptions, id: \.id) { sub in
                            subscriptionRow(sub, viewModel: viewModel)
                        }
                    }
                }

                if !viewModel.inactiveSubscriptions.isEmpty {
                    Section(isExpanded: $inactiveSectionExpanded) {
                        ForEach(viewModel.inactiveSubscriptions, id: \.id) { sub in
                            subscriptionRow(sub, viewModel: viewModel)
                        }
                    } header: {
                        Button {
                            withAnimation { inactiveSectionExpanded.toggle() }
                        } label: {
                            HStack {
                                Text(String(localized: "Inactive"))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: inactiveSectionExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
        }
    }

    // MARK: - Monthly cost card

    private func monthlyCostCard(_ viewModel: SubscriptionsViewModel) -> some View {
        SummaryCard(
            title: String(localized: "Est. Monthly Cost"),
            icon: "calendar.circle.fill",
            amount: Money(minorUnits: viewModel.monthlyCostMinor, currencyCode: viewModel.homeCurrencyCode).formatted(),
            amountMinor: viewModel.monthlyCostMinor,
            isLoading: viewModel.monthlyCostIsLoading,
            subtitle: String(localized: "Active subscriptions only")
        )
    }

    // MARK: - Row

    private func subscriptionRow(_ sub: Subscription, viewModel: SubscriptionsViewModel) -> some View {
        SubscriptionRowView(
            subscription: sub,
            notificationsAuthorized: viewModel.notificationsAuthorized,
            homeAmountMinor: viewModel.subscriptionHomeAmounts[sub.id],
            homeCurrencyCode: viewModel.homeCurrencyCode
        )
        .contentShape(Rectangle())
        .onTapGesture { viewModel.presentEdit(sub) }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                viewModel.deleteSubscription(sub)
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            switch sub.status {
            case .active:
                Button {
                    viewModel.pauseSubscription(sub)
                } label: {
                    Label(String(localized: "Pause"), systemImage: "pause.fill")
                }
                .tint(.orange)
            case .paused:
                Button {
                    viewModel.resumeSubscription(sub)
                } label: {
                    Label(String(localized: "Resume"), systemImage: "play.fill")
                }
                .tint(.green)
            case .cancelled:
                Button {
                    viewModel.resumeSubscription(sub)
                } label: {
                    Label(String(localized: "Restore"), systemImage: "arrow.uturn.left")
                }
                .tint(.blue)
            }
        }
    }

    // MARK: - Empty state

    private func emptyState(_ viewModel: SubscriptionsViewModel) -> some View {
        ContentUnavailableView {
            Label(String(localized: "No Subscriptions"), systemImage: "repeat.circle")
        } description: {
            Text(String(localized: "Add a subscription manually, or paste a billing email to detect it automatically."))
        } actions: {
            VStack(spacing: 10) {
                Button(String(localized: "Add Subscription")) {
                    viewModel.presentAdd()
                }
                .buttonStyle(.borderedProminent)
                Button(String(localized: "Scan from email or SMS")) {
                    viewModel.presentAutoDetect()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Sheet binding

    private var destinationBinding: Binding<SubscriptionsDestination?> {
        Binding(
            get: { viewModel?.destination },
            set: { viewModel?.destination = $0 }
        )
    }
}

#if DEBUG
#Preview {
    SubscriptionsView()
        .modelContainer(PreviewContainer.shared)
}
#endif
