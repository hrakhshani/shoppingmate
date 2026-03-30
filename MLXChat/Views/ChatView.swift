import SwiftUI
import PhotosUI

struct ChatView: View {
    @State private var viewModel = ChatViewModel()
    @State private var inputText = ""
    @State private var pendingImage: UIImage?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var showModelPicker = false
    @State private var showSettings = false
    @State private var settings = SettingsManager.shared
    @State private var selectedProducts: [SearchResult] = []
    @FocusState private var inputFocused: Bool

    private var visibleMessages: [ChatMessage] {
        viewModel.messages.filter { !$0.isHidden }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [.marmaladeBg, .marmaladeBg2, .marmaladeBg3],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Model header + thinking toggle
                    HStack {
                        Button {
                            showModelPicker = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: settings.loadedModelName != nil ? "circle.fill" : "circle")
                                    .font(.caption2)
                                    .foregroundStyle(settings.loadedModelName != nil ? Color.marmaladeMint : Color.marmaladeMuted)
                                if let name = settings.loadedModelName {
                                    Text(name)
                                        .lineLimit(1)
                                        .font(.subheadline)
                                        .foregroundStyle(Color.marmaladeCream)
                                } else {
                                    Text("Select a model")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.marmaladeMuted)
                                }
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(Color.marmaladeMuted)
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if viewModel.isThinkingModel {
                            Toggle(isOn: $viewModel.thinkingEnabled) {
                                Label("Think", systemImage: "brain")
                                    .font(.subheadline)
                            }
                            .toggleStyle(.button)
                            .buttonStyle(.bordered)
                            .tint(viewModel.thinkingEnabled ? Color.marmaladeAmber : Color.marmaladeMuted)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    Rectangle()
                        .fill(Color.marmaladeAmber.opacity(0.15))
                        .frame(height: 1)

                    // Messages
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(visibleMessages) { message in
                                    ChatBubbleView(
                                        message: message,
                                        onProductSelect: { product in
                                            if !selectedProducts.contains(where: { $0.id == product.id }) {
                                                selectedProducts.append(product)
                                            }
                                        },
                                        onQuestionnaireSubmit: { filled in
                                            viewModel.handleQuestionnaireSubmit(filled)
                                        },
                                        onTipsSubmit: { filled in
                                            viewModel.handleTipsSubmit(filled)
                                        }
                                    )
                                    .id(message.id)
                                }

                                if viewModel.isGenerating {
                                    HStack {
                                        ProgressView()
                                            .tint(Color.marmaladeAmber)
                                        if let status = viewModel.statusMessage {
                                            Text(status)
                                                .font(.caption)
                                                .foregroundStyle(Color.marmaladeMuted)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                    .id("generating")
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onTapGesture {
                            inputFocused = false
                        }
                        .onChange(of: visibleMessages.count) {
                            withAnimation {
                                if let last = visibleMessages.last {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                        .onChange(of: visibleMessages.last?.text) {
                            if let last = visibleMessages.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }

                    if let error = viewModel.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.45))
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                inputBar
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.marmaladeBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showSettings = true
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }

                        Divider()

                        Button(role: .destructive) {
                            viewModel.clearSession()
                            selectedProducts = []
                            inputText = ""
                        } label: {
                            Label("Clear Chat", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Color.marmaladeAmber)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
            .onChange(of: selectedPhoto) {
                loadPhoto()
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraView(image: $pendingImage)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showModelPicker) {
                ModelPickerView(viewModel: viewModel)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var productPlaceholder: some View {
        ZStack {
            Color.marmaladeBg2
            Image(systemName: "bag.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.marmaladeAmber.opacity(0.5))
        }
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.marmaladeAmber.opacity(0.15))
                .frame(height: 1)

            // Selected product thumbnails
            if !selectedProducts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedProducts) { product in
                            ZStack(alignment: .topTrailing) {
                                if let thumbURL = product.thumbnailURL,
                                   let url = URL(string: thumbURL) {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        default:
                                            productPlaceholder
                                        }
                                    }
                                } else {
                                    productPlaceholder
                                }
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.marmaladeAmber.opacity(0.4), lineWidth: 1)
                            )
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    selectedProducts.removeAll { $0.id == product.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.marmaladeBg, Color.marmaladeAmber)
                                }
                                .buttonStyle(.plain)
                                .offset(x: 5, y: -5)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
                .padding(.top, 6)
            }

            // Pending image preview
            if let image = pendingImage {
                HStack {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Button {
                        pendingImage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.marmaladeMuted)
                    }

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 6)
            }

            HStack(spacing: 8) {
                Menu {
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Photo Library", systemImage: "photo.on.rectangle")
                    }

                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera")
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.marmaladeAmber)
                }

                TextField("Message...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .foregroundStyle(Color.marmaladeCream)
                    .accentColor(Color.marmaladeAmber)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.black.opacity(0.35))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(Color.marmaladeAmber.opacity(0.2), lineWidth: 1)
                    )
                    .onSubmit {
                        if canSend { sendCurrentMessage() }
                    }

                if viewModel.isGenerating {
                    Button {
                        viewModel.stopGeneration()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color(red: 1, green: 0.4, blue: 0.4))
                    }
                } else {
                    Button {
                        sendCurrentMessage()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    canSend
                                    ? AnyShapeStyle(LinearGradient(
                                        colors: [.marmaladeAmber, Color(red: 224/255, green: 145/255, blue: 18/255)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing))
                                    : AnyShapeStyle(Color.marmaladeMuted.opacity(0.3))
                                )
                                .frame(width: 36, height: 36)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(canSend ? Color.marmaladeBg : Color.marmaladeMuted)
                        }
                    }
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color.marmaladeBg2.opacity(0.97))
    }

    private var canSend: Bool {
        !viewModel.isGenerating && settings.loadedModelId != nil &&
        (!inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingImage != nil || !selectedProducts.isEmpty)
    }

    private func sendCurrentMessage() {
        inputFocused = false
        var text = inputText
        let image = pendingImage
        inputText = ""
        pendingImage = nil
        selectedPhoto = nil

        if !selectedProducts.isEmpty {
            let productContext = selectedProducts.map { p -> String in
                var parts = [p.title]
                if let price = p.price, !price.isEmpty { parts.append(price) }
                if !p.description.isEmpty { parts.append(p.description) }
                parts.append(p.url)
                return parts.joined(separator: " · ")
            }.joined(separator: "\n")
            let prefix = "Product context:\n\(productContext)\n\n"
            text = prefix + text
            selectedProducts = []
        }

        // Check if we should show the product questionnaire first
        if viewModel.shouldShowProductQuestionnaire(for: text, hasImage: image != nil) {
            // Add the user message first
            let userMessage = ChatMessage(role: .user, text: text, image: image)
            viewModel.messages.append(userMessage)
            // Then show the questionnaire instead of immediately searching
            viewModel.showProductQuestionnaire(for: text)
            return
        }

        viewModel.generationTask = Task {
            await viewModel.sendMessage(text: text, image: image)
        }
    }

    private func loadPhoto() {
        guard let item = selectedPhoto else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                pendingImage = image
            }
        }
    }
}

// MARK: - Camera

struct CameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
