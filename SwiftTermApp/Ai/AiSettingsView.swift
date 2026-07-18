//
//  AiSettingsView.swift
//  SwiftTermApp
//
//  Settings UI for AI providers: list configured providers, pick the active
//  one, and add/edit providers (Anthropic, OpenAI and compatible endpoints,
//  Gemini) with keychain-backed API keys and a one-tap connectivity Test.
//

import SwiftUI

struct AiSettingsView: View {
    @ObservedObject var store = AiProviderStore.shared
    @State var editing: AiProviderConfig? = nil

    var body: some View {
        List {
            if store.providers.isEmpty {
                Section {
                    VStack (alignment: .leading, spacing: 8) {
                        Text ("No AI providers configured")
                        Text ("Add a provider with your own API key.  Keys are stored in the keychain and requests are only sent when you explicitly ask for them.")
                            .font (.subheadline)
                            .foregroundColor (.secondary)
                    }
                }
            } else {
                Section (header: Text ("Providers"), footer: Text ("The checkmark marks the active provider used by AI features.  Tap a provider to edit it.")) {
                    ForEach (store.providers) { provider in
                        Button (action: { editing = provider }) {
                            HStack {
                                Image (systemName: store.activeProviderId == provider.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor (store.activeProviderId == provider.id ? .accentColor : .secondary)
                                    .onTapGesture {
                                        store.activeProviderId = provider.id
                                    }
                                VStack (alignment: .leading) {
                                    Text (provider.name)
                                        .foregroundColor (.primary)
                                    Text (providerCaption (provider))
                                        .font (.caption)
                                        .foregroundColor (.secondary)
                                }
                                Spacer ()
                                Image (systemName: "chevron.right")
                                    .font (.caption)
                                    .foregroundColor (Color (.tertiaryLabel))
                            }
                        }
                    }
                    .onDelete { offsets in
                        for idx in offsets {
                            store.remove (store.providers [idx])
                        }
                    }
                }
            }
        }
        .listStyle (GroupedListStyle ())
        .navigationTitle ("AI Providers")
        .toolbar {
            ToolbarItem (placement: .navigationBarTrailing) {
                Menu {
                    Button ("Anthropic") { addProvider (.anthropic) }
                    Button ("OpenAI") { addProvider (.openai) }
                    Button ("Google Gemini") { addProvider (.gemini) }
                    Divider ()
                    Button ("Anthropic-compatible…") { addProvider (.anthropic, name: "Anthropic-compatible") }
                    Button ("OpenAI-compatible…") { addProvider (.openai, name: "OpenAI-compatible") }
                } label: {
                    Image (systemName: "plus")
                }
            }
        }
        .sheet (item: $editing) { provider in
            AiProviderEditor (store: store, config: provider)
        }
    }

    func providerCaption (_ provider: AiProviderConfig) -> String {
        var parts = [provider.kind.displayName, provider.model]
        if provider.isCustomEndpoint {
            parts.append (provider.baseUrl)
        }
        return parts.joined (separator: " · ")
    }

    func addProvider (_ kind: AiProviderKind, name: String? = nil) {
        // Not stored until the editor saves
        editing = AiProviderConfig.makeDefault (kind: kind, name: name)
    }
}

struct AiProviderEditor: View {
    @Environment (\.presentationMode) var presentationMode
    var store: AiProviderStore
    @State var config: AiProviderConfig
    @State var apiKey: String = ""
    @State var keyLoaded = false
    @State var testState: TestState = .idle

    enum TestState {
        case idle
        case running
        case success (String, String?)
        case failure (String)
    }

    init (store: AiProviderStore, config: AiProviderConfig) {
        self.store = store
        self._config = State (initialValue: config)
    }

    var body: some View {
        NavigationView {
            Form {
                Section (header: Text ("Provider")) {
                    TextField ("Name", text: $config.name)
                    HStack {
                        Text ("Kind")
                        Spacer ()
                        Text (config.kind.displayName)
                            .foregroundColor (.secondary)
                    }
                }
                Section (header: Text ("Endpoint"), footer: Text ("Change the base URL to use a compatible proxy or gateway.")) {
                    TextField ("Base URL", text: $config.baseUrl)
                        .keyboardType (.URL)
                        .autocapitalization (.none)
                        .disableAutocorrection (true)
                    if config.isCustomEndpoint {
                        Button ("Reset to default endpoint") {
                            config.baseUrl = config.kind.defaultBaseUrl
                        }
                    }
                }
                Section (header: Text ("Model")) {
                    HStack {
                        TextField ("Model", text: $config.model)
                            .autocapitalization (.none)
                            .disableAutocorrection (true)
                        Menu {
                            ForEach (config.kind.suggestedModels, id: \.self) { model in
                                Button (model) { config.model = model }
                            }
                        } label: {
                            Image (systemName: "chevron.up.chevron.down")
                        }
                    }
                }
                Section (header: Text ("API Key"), footer: Text ("Stored in the keychain, never in settings files.")) {
                    SecureField ("API key", text: $apiKey)
                        .autocapitalization (.none)
                        .disableAutocorrection (true)
                }
                Section {
                    Button (action: runTest) {
                        HStack {
                            Text ("Test")
                            Spacer ()
                            testStatusView
                        }
                    }
                    .disabled (isTestDisabled)
                }
            }
            .navigationTitle (config.name)
            .navigationBarTitleDisplayMode (.inline)
            .toolbar {
                ToolbarItem (placement: .cancellationAction) {
                    Button ("Cancel") {
                        presentationMode.wrappedValue.dismiss ()
                    }
                }
                ToolbarItem (placement: .confirmationAction) {
                    Button ("Save") {
                        save ()
                    }
                    .disabled (config.name.isEmpty || config.baseUrl.isEmpty || config.model.isEmpty)
                }
            }
            .onAppear {
                if !keyLoaded {
                    apiKey = store.apiKey (for: config)
                    keyLoaded = true
                }
            }
        }
    }

    var isTestDisabled: Bool {
        if case .running = testState { return true }
        return apiKey.isEmpty || config.baseUrl.isEmpty
    }

    @ViewBuilder
    var testStatusView: some View {
        switch testState {
        case .idle:
            EmptyView ()
        case .running:
            ProgressView ()
        case .success (let summary, let warning):
            VStack (alignment: .trailing) {
                Label (summary, systemImage: "checkmark.circle.fill")
                    .foregroundColor (.green)
                    .font (.caption)
                if let warning = warning {
                    Text (warning)
                        .font (.caption2)
                        .foregroundColor (.orange)
                }
            }
        case .failure (let message):
            Label (message, systemImage: "xmark.circle.fill")
                .foregroundColor (.red)
                .font (.caption)
        }
    }

    func runTest () {
        testState = .running
        let client = AiClient (config: config, apiKey: apiKey)
        Task {
            do {
                let result = try await client.test ()
                await MainActor.run {
                    testState = .success (result.summary, result.warning)
                }
            } catch {
                await MainActor.run {
                    testState = .failure (error.localizedDescription)
                }
            }
        }
    }

    func save () {
        store.upsert (config)
        store.setApiKey (for: config, key: apiKey)
        presentationMode.wrappedValue.dismiss ()
    }
}

struct AiSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            AiSettingsView ()
        }
    }
}
