//
//  ComputerInfoView.swift
//  Artemis
//
//  Get Info for a PC: the Mac app's fields (addresses, MAC, UUID, pairing, running app, port).
//

import SwiftUI

struct ComputerInfoView: View {
    let computerID: String
    @Environment(ComputerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(store.info(for: computerID).enumerated()), id: \.offset) { _, row in
                        // Label above the value at accessibility sizes, so long addresses keep the width
                        if typeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.label).foregroundStyle(.secondary)
                                Text(row.value).textSelection(.enabled)
                            }
                            .accessibilityElement(children: .combine)
                        } else {
                            LabeledContent(row.label) {
                                Text(row.value)
                                    .textSelection(.enabled)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                } footer: {
                    Note("Touch and hold a value to copy it.")
                }
            }
            .navigationTitle(store.computer(computerID)?.name ?? "PC")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("info.list")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("info.done")
                }
            }
        }
    }
}
