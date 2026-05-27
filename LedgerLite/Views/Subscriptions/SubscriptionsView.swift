import SwiftUI
import SwiftData

struct SubscriptionsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: SubscriptionsViewModel?
    @State private var inactiveSectionExpanded = false
    // C3
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
            .navigationBarTitleDisplayMode(.large)  // A9
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
                UINotificationFeedbackGenerator().notificationOccurred(.error)  // C1
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
                monthlyCostCard(viewModel)

                Section(String(localized: "Active")) {
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
        }
    }

    // MARK: - Monthly cost card

    @ViewBuilder
    private func monthlyCostCard(_ viewModel: SubscriptionsViewModel) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Est. Monthly Cost"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if viewModel.monthlyCostIsLoading {
                    ProgressView().frame(height: 44)
                } else {
                    Text(Money(minorUnits: viewModel.monthlyCostMinor, currencyCode: viewModel.homeCurrencyCode).formatted())
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Text(String(localized: "Active subscriptions only"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Row + swipe actions

    private func subscriptionRow(_ sub: Subscription, viewModel: SubscriptionsViewModel) -> some View {
        SubscriptionRowView(subscription: sub, notificationsAuthorized: viewModel.notificationsAuthorized)
            .contentShape(Rectangle())
            .onTapGesture { viewModel.presentEdit(sub) }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()  // C1
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
            Text(String(localized: "Tap + to track your first subscription."))
        } actions: {
            Button(String(localized: "Add Subscription")) {
                viewModel.presentAdd()
            }
            .buttonStyle(.borderedProminent)
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
