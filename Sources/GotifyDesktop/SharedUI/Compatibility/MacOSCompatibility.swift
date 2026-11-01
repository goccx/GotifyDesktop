import AppKit
import SwiftUI

/// Isolates macOS 12 vs macOS 13+ SwiftUI container and modifier differences in one adapter file
/// so feature views remain free of availability branches while preserving 100% native behavior.
struct SplitNavigationContainer<Sidebar: View, Detail: View>: View {
    private let sidebar: Sidebar
    private let detail: Detail

    init(
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        self.detail = detail()
    }

    var body: some View {
        if #available(macOS 13.0, *) {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 210, ideal: 232, max: 260)
            } detail: {
                detail
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            NavigationView {
                sidebar
                    .frame(minWidth: 210, idealWidth: 232, maxWidth: 260)
                detail
            }
            .navigationViewStyle(DoubleColumnNavigationViewStyle())
        }
    }
}

struct CompatibleSettingsForm<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(macOS 13.0, *) {
            Form {
                content
            }
            .formStyle(.grouped)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content
                }
                .padding(20)
            }
        }
    }
}

struct CompatibleSettingsSection<Header: View, Content: View>: View {
    private let header: Header
    private let content: Content

    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Header
    ) {
        self.content = content()
        self.header = header()
    }

    init(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) where Header == Text {
        self.content = content()
        self.header = Text(title)
    }

    var body: some View {
        if #available(macOS 13.0, *) {
            Section {
                content
            } header: {
                header
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                header
                    .font(.headline)
                    .padding(.horizontal, 4)

                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }
}

struct CompatibleLabeledContent<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        if #available(macOS 13.0, *) {
            LabeledContent(title) {
                content
            }
        } else {
            HStack(spacing: 12) {
                Text(title)
                Spacer(minLength: 12)
                content
            }
        }
    }
}

extension View {
    @ViewBuilder
    func compatibleHiddenListRowSeparator() -> some View {
        if #available(macOS 13.0, *) {
            self.listRowSeparator(.hidden)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatibleReservedTwoLineLimit() -> some View {
        if #available(macOS 13.0, *) {
            self.lineLimit(2, reservesSpace: true)
        } else {
            self.lineLimit(2)
                .frame(minHeight: 34, alignment: .topLeading)
        }
    }
}
