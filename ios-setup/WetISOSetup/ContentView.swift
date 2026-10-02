import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = SetupModel()
    @State private var showISOPicker = false
    @State private var showXEXPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("1. GitHub token") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Classic token with repo + workflow scopes.")
                                .font(.footnote).foregroundColor(.secondary)
                            SecureField("ghp_…", text: $model.token)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                            Button("Connect") {
                                Task { await model.connectToken() }
                            }.disabled(model.token.isEmpty)
                            Text(model.tokenStatus).font(.footnote).foregroundColor(.secondary)
                        }
                    }

                    GroupBox("2. Repository") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("owner", text: $model.owner)
                                    .textFieldStyle(.roundedBorder)
                                Text("/")
                                TextField("repo", text: $model.repo)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Button("Check") {
                                Task { await model.checkRepo() }
                            }
                            Text(model.repoStatus).font(.footnote).foregroundColor(.secondary)
                        }
                    }

                    GroupBox("3. Your ISO") {
                        VStack(alignment: .leading, spacing: 8) {
                            Button("Select your WET Xbox 360 ISO") { showISOPicker = true }
                                .buttonStyle(.borderedProminent)
                            Button("or select default.xex directly") { showXEXPicker = true }
                                .font(.footnote)
                            Text(model.isoStatus).font(.footnote).foregroundColor(.secondary)
                        }
                    }

                    GroupBox("4. Encrypt, upload & build") {
                        VStack(alignment: .leading, spacing: 8) {
                            Button("Do everything") {
                                Task { await model.doEverything() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.canGo || model.running)
                            if let pp = model.passphrase {
                                Text("Passphrase:").font(.footnote).bold()
                                Text(pp).font(.footnote).textSelection(.enabled)
                                Text("Save this in your password manager.")
                                    .font(.footnote).foregroundColor(.orange)
                            }
                            ScrollView {
                                Text(model.log)
                                    .font(.system(.footnote, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: 220)
                            if let url = model.actionsURL {
                                Link("Watch the build on GitHub →", destination: url)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Wet ISO Setup")
            .sheet(isPresented: $showISOPicker) {
                DocumentPicker(types: [.data]) { url in
                    Task { await model.handleISO(url) }
                }
            }
            .sheet(isPresented: $showXEXPicker) {
                DocumentPicker(types: [.data]) { url in
                    Task { await model.handleXEXFile(url) }
                }
            }
        }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    var types: [UTType]
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        vc.delegate = context.coordinator
        vc.allowsMultipleSelection = false
        return vc
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
