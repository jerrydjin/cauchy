import SwiftUI

struct WorkspaceLayoutView: View {
    @Bindable var workspace: WorkspaceViewModel

    var body: some View {
        ReaderWorkspaceView(workspace: workspace)
    }
}
