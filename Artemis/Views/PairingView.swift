//
//  PairingView.swift
//  Artemis
//
//  The PIN to enter on the host, large on its own line, as on the Mac.
//  Closes by itself when pairing finishes.
//

import SwiftUI

struct PairingView: View {
    let pairing: PairingInfo
    @Environment(ComputerStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                        .padding(.top, 8)
                    Text("Enter this PIN on your host PC:")
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(pairing.pin)
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .tracking(10)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .glassEffect(.regular, in: .rect(cornerRadius: 24))
                        .accessibilityLabel(pairing.pin.map(String.init).joined(separator: " "))
                        .accessibilityIdentifier("pairing.pin")
                        .textSelection(.enabled)
                    Text("With Apollo or Sunshine, enter it on the PIN page of the host's web UI. This closes by itself once you're paired.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    ProgressView()
                }
                .padding(24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Pair with \(pairing.hostName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { store.cancelPairing() }
                        .accessibilityIdentifier("pairing.cancel")
                }
            }
        }
        .presentationDetents([.large])
    }
}
