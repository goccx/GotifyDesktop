import AppKit
import SwiftUI

/// Unified macOS 12+ container and view helpers with zero OS-version availability branches,
/// ensuring identical runtime behavior across macOS 12 through macOS 15+.
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
        NavigationView {
            sidebar
                .frame(minWidth: 210, idealWidth: 232, maxWidth: 260)
            detail
        }
        .navigationViewStyle(DoubleColumnNavigationViewStyle())
    }
}

struct CompatibleSettingsForm<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .padding(20)
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

struct CompatibleLabeledContent<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            content
        }
    }
}

extension View {
    func compatibleHiddenListRowSeparator() -> some View {
        self
    }

    func compatibleReservedTwoLineLimit() -> some View {
        self.lineLimit(2)
            .frame(minHeight: 34, alignment: .topLeading)
    }
}
