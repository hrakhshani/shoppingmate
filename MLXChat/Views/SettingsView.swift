import SwiftUI

struct SettingsView: View {
    @State private var settings = SettingsManager.shared
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case braveAPIKey
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.marmaladeBg.ignoresSafeArea()

                List {
                    if !settings.activeModelDownloads.isEmpty {
                        Section {
                            ForEach(settings.activeModelDownloads, id: \.hfId) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(settings.modelDisplayName(hfId: item.hfId))
                                            .font(.subheadline)
                                            .foregroundStyle(Color.marmaladeCream)
                                        Text("Downloading and preparing model...")
                                            .font(.caption2)
                                            .foregroundStyle(Color.marmaladeMuted)
                                    }
                                    Spacer()
                                    Text("\(Int((item.progress * 100).rounded()))%")
                                        .font(.caption2)
                                        .monospacedDigit()
                                        .foregroundStyle(Color.marmaladeMuted)
                                    ProgressView(value: item.progress)
                                        .progressViewStyle(.circular)
                                        .tint(Color.marmaladeAmber)
                                        .frame(width: 18, height: 18)
                                    Button {
                                        settings.cancelModelDownload(hfId: item.hfId)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(Color.marmaladeMuted)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .listRowBackground(Color.marmaladeBg2)
                            }
                        } header: {
                            Text("Active Downloads")
                                .foregroundStyle(Color.marmaladeAmber)
                                .textCase(.uppercase)
                        } footer: {
                            Text("Downloads continue in the background until they complete or you cancel them.")
                                .foregroundStyle(Color.marmaladeMuted)
                        }
                    }

                    Section {
                        if let name = settings.loadedModelName {
                            HStack {
                                Image(systemName: "circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(Color.marmaladeMint)
                                Text(name)
                                    .foregroundStyle(Color.marmaladeCream)
                            }
                            .listRowBackground(Color.marmaladeBg2)
                        } else {
                            Text("No model loaded")
                                .foregroundStyle(Color.marmaladeMuted)
                                .listRowBackground(Color.marmaladeBg2)
                        }
                    } header: {
                        Text("Currently Loaded")
                            .foregroundStyle(Color.marmaladeAmber)
                            .textCase(.uppercase)
                    }

                    Section {
                        if settings.cachedModels.isEmpty {
                            Text("No models downloaded")
                                .foregroundStyle(Color.marmaladeMuted)
                                .listRowBackground(Color.marmaladeBg2)
                        } else {
                            ForEach(settings.cachedModels) { model in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.displayName)
                                            .font(.subheadline)
                                            .foregroundStyle(Color.marmaladeCream)
                                        Text(model.id)
                                            .font(.caption2)
                                            .foregroundStyle(Color.marmaladeMuted.opacity(0.7))
                                    }
                                    Spacer()
                                    if settings.loadedModelId == model.id {
                                        Text("Loaded")
                                            .font(.caption2)
                                            .foregroundStyle(Color.marmaladeMint)
                                            .padding(.trailing, 4)
                                    }
                                    Text(model.sizeFormatted)
                                        .font(.caption)
                                        .foregroundStyle(Color.marmaladeMuted)
                                }
                                .listRowBackground(Color.marmaladeBg2)
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    settings.deleteModel(model: settings.cachedModels[index])
                                }
                            }

                            HStack {
                                Text("Total")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(Color.marmaladeCream)
                                Spacer()
                                Text(settings.totalCacheSize)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(Color.marmaladeMuted)
                            }
                            .listRowBackground(Color.marmaladeBg2)
                        }
                    } header: {
                        Text("Downloaded Models")
                            .foregroundStyle(Color.marmaladeAmber)
                            .textCase(.uppercase)
                    } footer: {
                        Text("Swipe left to delete. Models will re-download when needed.")
                            .foregroundStyle(Color.marmaladeMuted)
                    }

                    Section {
                        Picker("GPU Memory Limit", selection: $settings.gpuMemoryLimitGB) {
                            ForEach(settings.gpuMemoryLimitOptions, id: \.self) { gb in
                                Text("\(gb) GB").tag(gb)
                                    .foregroundStyle(Color.marmaladeCream)
                            }
                        }
                        .foregroundStyle(Color.marmaladeCream)
                        .tint(Color.marmaladeAmber)
                        .listRowBackground(Color.marmaladeBg2)

                        Picker("Model Download Limit", selection: $settings.maxModelDownloadSizeGB) {
                            ForEach(settings.modelDownloadLimitOptions, id: \.self) { gb in
                                if gb == 0 {
                                    Text("No Limit").tag(gb)
                                        .foregroundStyle(Color.marmaladeCream)
                                } else {
                                    Text("\(gb) GB").tag(gb)
                                        .foregroundStyle(Color.marmaladeCream)
                                }
                            }
                        }
                        .foregroundStyle(Color.marmaladeCream)
                        .tint(Color.marmaladeAmber)
                        .listRowBackground(Color.marmaladeBg2)
                    } header: {
                        Text("Memory")
                            .foregroundStyle(Color.marmaladeAmber)
                            .textCase(.uppercase)
                    } footer: {
                        Text("GPU Memory Limit controls how much memory MLX may use at runtime and requires an app restart. Model Download Limit controls which models are offered for new downloads in the picker.")
                            .foregroundStyle(Color.marmaladeMuted)
                    }

                    Section {
                        Picker("Context Size", selection: $settings.contextSize) {
                            Text("4K").tag(4096)
                            Text("8K").tag(8192)
                            Text("12K").tag(12288)
                            Text("16K").tag(16384)
                            Text("20K").tag(20480)
                            Text("24K").tag(24576)
                            Text("28K").tag(28672)
                            Text("32K").tag(32768)
                        }
                        .foregroundStyle(Color.marmaladeCream)
                        .tint(Color.marmaladeAmber)
                        .listRowBackground(Color.marmaladeBg2)

                        Toggle("Stream Responses", isOn: $settings.streamingEnabled)
                            .foregroundStyle(Color.marmaladeCream)
                            .tint(Color.marmaladeAmber)
                            .listRowBackground(Color.marmaladeBg2)
                    } header: {
                        Text("Generation")
                            .foregroundStyle(Color.marmaladeAmber)
                            .textCase(.uppercase)
                    } footer: {
                        Text("Context window size affects maximum response length. Streaming shows tokens as they are generated.")
                            .foregroundStyle(Color.marmaladeMuted)
                    }

                    Section {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Max Image Dimension")
                                    .foregroundStyle(Color.marmaladeCream)
                                Spacer()
                                Text("\(settings.maxImageDimension) px")
                                    .foregroundStyle(Color.marmaladeMuted)
                            }
                            Slider(
                                value: Binding(
                                    get: { Double(settings.maxImageDimension) },
                                    set: { settings.maxImageDimension = Int($0) }
                                ),
                                in: 128...1024,
                                step: 64
                            )
                            .tint(Color.marmaladeAmber)
                        }
                        .listRowBackground(Color.marmaladeBg2)

                        VStack(alignment: .leading) {
                            HStack {
                                Text("JPEG Quality")
                                    .foregroundStyle(Color.marmaladeCream)
                                Spacer()
                                Text(String(format: "%.0f%%", settings.jpegQuality * 100))
                                    .foregroundStyle(Color.marmaladeMuted)
                            }
                            Slider(
                                value: $settings.jpegQuality,
                                in: 0.1...1.0,
                                step: 0.1
                            )
                            .tint(Color.marmaladeAmber)
                        }
                        .listRowBackground(Color.marmaladeBg2)
                    } header: {
                        Text("Image Settings")
                            .foregroundStyle(Color.marmaladeAmber)
                            .textCase(.uppercase)
                    } footer: {
                        Text("Smaller dimensions and lower quality reduce memory usage but may affect model accuracy.")
                            .foregroundStyle(Color.marmaladeMuted)
                    }

                    Section {
                        Toggle("Enable Tools", isOn: $settings.toolsEnabled)
                            .foregroundStyle(Color.marmaladeCream)
                            .tint(Color.marmaladeAmber)
                            .listRowBackground(Color.marmaladeBg2)

                        if settings.toolsEnabled {
                            SecureField("Brave Search API Key", text: $settings.braveAPIKey)
                                .textContentType(.password)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .focused($focusedField, equals: .braveAPIKey)
                                .foregroundStyle(Color.marmaladeCream)
                                .listRowBackground(Color.marmaladeBg2)
                        }
                    } header: {
                        Text("Tools")
                            .foregroundStyle(Color.marmaladeAmber)
                            .textCase(.uppercase)
                    } footer: {
                        Text("Tools let the model search the web and fetch URLs. A Brave API key enables web search (get one free at brave.com/search/api).")
                            .foregroundStyle(Color.marmaladeMuted)
                    }

                    Section {
                        let totalRAM = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
                        let availableRAM = totalRAM * 0.6
                        MetricRow(label: "App Version", value: settings.appVersionString)
                        MetricRow(label: "Build Marker", value: settings.runtimeBuildMarker)
                        MetricRow(label: "Total RAM", value: String(format: "%.1f GB", totalRAM))
                        MetricRow(label: "Available for models", value: String(format: "%.1f GB", availableRAM))
                    } header: {
                        Text("Device Info")
                            .foregroundStyle(Color.marmaladeAmber)
                            .textCase(.uppercase)
                    }
                }
                .scrollContentBackground(.hidden)
                .tint(Color.marmaladeAmber)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.marmaladeBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .scrollDismissesKeyboard(.immediately)
            .onAppear {
                settings.refreshCachedModels()
            }
            .refreshable {
                focusedField = nil
                settings.refreshCachedModels()
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                    .foregroundStyle(Color.marmaladeAmber)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.marmaladeCream)
            Spacer()
            Text(value)
                .foregroundStyle(Color.marmaladeMuted)
        }
        .listRowBackground(Color.marmaladeBg2)
    }
}
