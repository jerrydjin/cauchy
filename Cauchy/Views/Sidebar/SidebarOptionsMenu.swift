import SwiftUI

struct SidebarOptionsMenu: View {
    @Bindable var workspace: WorkspaceViewModel

    var body: some View {
        Menu {
            if workspace.sidebarVisible {
                Button("Hide Sidebar") {
                    workspace.sidebarVisible = false
                }
            } else {
                Button("Show Sidebar") {
                    workspace.sidebarVisible = true
                }
            }

            Divider()

            ForEach(SidebarContentMode.allCases.filter { $0 != .highlightsAndNotes }, id: \.self) { mode in
                Button {
                    workspace.sidebarContentMode = mode
                    workspace.sidebarVisible = true
                } label: {
                    sidebarMenuLabel(
                        title: mode.title,
                        isSelected: workspace.sidebarContentMode == mode
                    )
                }
            }

            Divider()

            ForEach(PDFPageLayoutMode.allCases, id: \.self) { mode in
                Button {
                    workspace.pdfPageLayoutMode = mode
                } label: {
                    sidebarMenuLabel(
                        title: mode.title,
                        isSelected: workspace.pdfPageLayoutMode == mode
                    )
                }
            }
        } label: {
            Image(systemName: "sidebar.leading")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 32)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .help("Sidebar and page layout")
    }

    private func sidebarMenuLabel(title: String, isSelected: Bool) -> some View {
        HStack {
            Image(systemName: "checkmark")
                .opacity(isSelected ? 1 : 0)
                .frame(width: 12)
            Text(title)
        }
    }
}
