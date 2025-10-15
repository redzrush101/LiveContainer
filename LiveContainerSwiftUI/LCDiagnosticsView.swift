//
//  LCDiagnosticsView.swift
//  LiveContainerSwiftUI
//
//  View for exporting and managing diagnostic logs
//

import SwiftUI
import UniformTypeIdentifiers

struct LCDiagnosticsView: View {
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var showClearConfirmation = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    var body: some View {
        List {
            Section {
                Text("lc.diagnostics.description".loc)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            
            Section("lc.diagnostics.actions".loc) {
                Button {
                    exportDiagnostics()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("lc.diagnostics.export".loc)
                        Spacer()
                        if isExporting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isExporting)
                
                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("lc.diagnostics.clearLogs".loc)
                    }
                }
            }
            
            Section("lc.diagnostics.info".loc) {
                HStack {
                    Text("lc.diagnostics.logLocation".loc)
                    Spacer()
                    if let logURL = LCLogger.currentLogFileURL() {
                        Text(logURL.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                HStack {
                    Text("lc.diagnostics.logSize".loc)
                    Spacer()
                    Text(formattedLogSize())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("lc.diagnostics.privacy".loc) {
                Text("lc.diagnostics.privacyNote".loc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("lc.diagnostics.title".loc)
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .alert("lc.diagnostics.clearConfirmTitle".loc, isPresented: $showClearConfirmation) {
            Button("lc.common.cancel".loc, role: .cancel) {}
            Button("lc.diagnostics.clearConfirm".loc, role: .destructive) {
                clearLogs()
            }
        } message: {
            Text("lc.diagnostics.clearConfirmMessage".loc)
        }
        .alert("lc.common.error".loc, isPresented: $showError) {
            Button("lc.common.ok".loc, role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }
    
    private func exportDiagnostics() {
        isExporting = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSError?
            let url = LCLogger.exportDiagnostics(&error)
            
            DispatchQueue.main.async {
                isExporting = false
                
                if let error = error {
                    errorMessage = error.localizedDescription
                    showError = true
                } else if let url = url {
                    exportURL = url
                    showShareSheet = true
                    
                    // Log the export action
                    LCLogger.info(category: .general, "Diagnostics exported successfully")
                }
            }
        }
    }
    
    private func clearLogs() {
        LCLogger.clearLogs()
        LCLogger.info(category: .general, "Logs cleared by user")
    }
    
    private func formattedLogSize() -> String {
        guard let logURL = LCLogger.currentLogFileURL() else {
            return "N/A"
        }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: logURL.path)
            if let fileSize = attributes[FileAttributeKey.size] as? UInt64 {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                return formatter.string(fromByteCount: Int64(fileSize))
            }
        } catch {}
        
        return "N/A"
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// Add localization strings
extension String {
    static let diagnosticsStrings: [String: String] = [
        "lc.diagnostics.title": "Diagnostics",
        "lc.diagnostics.description": "Export diagnostic logs to help troubleshoot issues. Sensitive information like passwords and certificates will be automatically redacted.",
        "lc.diagnostics.actions": "Actions",
        "lc.diagnostics.export": "Export Diagnostics",
        "lc.diagnostics.clearLogs": "Clear Logs",
        "lc.diagnostics.info": "Information",
        "lc.diagnostics.logLocation": "Current Log File",
        "lc.diagnostics.logSize": "Log Size",
        "lc.diagnostics.privacy": "Privacy",
        "lc.diagnostics.privacyNote": "Exported diagnostics are redacted to remove passwords, certificate data, and keychain tokens. However, please review the file before sharing publicly.",
        "lc.diagnostics.clearConfirmTitle": "Clear All Logs?",
        "lc.diagnostics.clearConfirmMessage": "This will permanently delete all diagnostic logs. This action cannot be undone.",
        "lc.diagnostics.clearConfirm": "Clear",
    ]
}
