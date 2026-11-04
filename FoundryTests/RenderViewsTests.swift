import XCTest
import SwiftUI
@testable import Foundry

/// Draws the new screens to PNGs for a visual check, only when TEST_RUNNER_RENDER_DIR is set.
/// Runs inside the test host: nothing is launched, the Keychain isn't read, and the windows are
/// transparent and off every display.
@MainActor
final class RenderViewsTests: XCTestCase {
    func testRenderNewScreens() throws {
        guard let path = ProcessInfo.processInfo.environment["RENDER_DIR"], !path.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_RENDER_DIR to render.")
        }
        let dir = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = AppModel.shared
        model.store.loadForPreview(SampleData.items(now: Date()), settings: SampleData.settings)
        for (name, look) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let ap = NSAppearance(named: look)!
            let full = CGSize(width: 1100, height: 720)
            ScreenshotRenderer.render(KanbanView().environment(model), size: full, appearance: ap, to: dir.appending(path: "board-\(name).png"))
            ScreenshotRenderer.render(MatrixView().environment(model), size: full, appearance: ap, to: dir.appending(path: "matrix-\(name).png"))
            ScreenshotRenderer.render(FocusView(todoId: "e").environment(model), size: CGSize(width: 800, height: 640), appearance: ap, to: dir.appending(path: "focus-\(name).png"))
            ScreenshotRenderer.render(HabitsView().environment(model), size: CGSize(width: 800, height: 560), appearance: ap, to: dir.appending(path: "habits-\(name).png"))
            ScreenshotRenderer.render(CommitmentDetail(id: "c").environment(model), size: CGSize(width: 640, height: 1150), appearance: ap, to: dir.appending(path: "detail-\(name).png"))
            for item in [SidebarItem.today, .upcoming, .anytime] {
                model.selection = item
                ScreenshotRenderer.render(MainWindow().environment(model), size: CGSize(width: 1280, height: 760), appearance: ap, to: dir.appending(path: "window-\(item.rawValue)-\(name).png"), titled: true)
            }
            ScreenshotRenderer.render(MenuBarPanel().environment(model), size: nil, width: 400, appearance: ap, to: dir.appending(path: "menubar-\(name).png"))
        }
    }
}
