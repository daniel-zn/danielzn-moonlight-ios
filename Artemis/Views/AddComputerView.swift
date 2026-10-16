//
//  AddComputerView.swift
//  Artemis
//

import SwiftUI

struct AddComputerView: View {
    @Environment(ComputerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var address = ""
    @State private var adding = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("IP address or hostname", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focused)
                        .onSubmit(add)
                        .disabled(adding)
                        .accessibilityIdentifier("add.address")
                } header: {
                    Text("Add a computer by its IP address or hostname")
                } footer: {
                    Text("Artemis finds PCs running Apollo or Sunshine on your network by itself. Add one here if it doesn't show up. Include the port if the host doesn't use the default one.")
                }
            }
            .navigationTitle("Add PC Manually")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if adding {
                        ProgressView()
                    } else {
                        Button("Add", systemImage: "checkmark", action: add)
                            .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("add.confirm")
                    }
                }
            }
            .alert("Add PC Manually", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Help") { openURL(Links.troubleshooting) }
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
            .onAppear { focused = true }
        }
    }

    private func add() {
        guard !address.trimmingCharacters(in: .whitespaces).isEmpty, !adding else { return }
        adding = true
        store.addComputer(address: address) { message in
            adding = false
            if let message {
                error = message
            } else {
                dismiss()
            }
        }
    }
}
