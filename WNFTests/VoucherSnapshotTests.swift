import CoreImage
import SwiftUI
import XCTest
@testable import WNF

/// Renders the two voucher share cards to PNG via the same `ImageRenderer`
/// pipeline the app's export path uses. When the `WNF_SNAPSHOT_DIR`
/// environment variable is set, the PNGs are written there so design passes
/// can inspect the exact export pixels without driving the UI. Without the
/// variable the tests still assert that rendering succeeds.
@MainActor
final class VoucherSnapshotTests: XCTestCase {
    private var snapshotDirectory: URL? {
        guard let path = ProcessInfo.processInfo.environment["WNF_SNAPSHOT_DIR"], !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func render(_ view: some View, width: CGFloat, name: String) throws {
        let image = try XCTUnwrap(
            WNFShareImageRenderer.render(
                view
                    .frame(width: width)
                    .environment(\.colorScheme, .light),
                width: width,
                scale: 3
            ),
            "\(name) should rasterize"
        )
        XCTAssertGreaterThan(image.size.height, 100, "\(name) should have real content")

        guard let dir = snapshotDirectory else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: dir.appendingPathComponent("\(name).png"))
    }

    func testShareImageRendererPreservesVerticalOrientation() throws {
        let image = try XCTUnwrap(
            WNFShareImageRenderer.render(
                VStack(spacing: 0) {
                    Color.red.frame(height: 20)
                    Color.blue.frame(height: 20)
                }
                .frame(width: 40, height: 40),
                width: 40,
                scale: 1
            )
        )

        let top = try pixelRGBA(in: image, x: 20, yFromTop: 5)
        let bottom = try pixelRGBA(in: image, x: 20, yFromTop: 35)

        XCTAssertGreaterThan(top.red, top.blue, "logical top should remain red")
        XCTAssertGreaterThan(bottom.blue, bottom.red, "logical bottom should remain blue")
    }

    private func pixelRGBA(
        in image: UIImage,
        x: CGFloat,
        yFromTop: CGFloat
    ) throws -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        let ciImage = try XCTUnwrap(CIImage(image: image))
        let sampleBounds = CGRect(
            x: x,
            y: ciImage.extent.height - yFromTop - 1,
            width: 1,
            height: 1
        )
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(
            ciImage,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: sampleBounds,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }

    func testDailyStatementVoucherRenders() throws {
        let day = WageCalculator.compute(
            monthlySalary: 12000,
            workdaysPerMonth: 22,
            workStart: DateComponents.minuteInDay(9 * 60),
            workEnd: DateComponents.minuteInDay(18 * 60),
            lunchStart: DateComponents.minuteInDay(12 * 60),
            lunchEnd: DateComponents.minuteInDay(13 * 60),
            hasLunchBreak: true,
            now: DateComponents(hour: 15, minute: 24, second: 30)
        )

        try render(
            WonangfeiShareCard(
                day: day,
                copy: .default,
                hidesSensitiveInfo: false,
                showsControls: false,
                onTogglePrivacy: {},
                onShare: {},
                onDismiss: {}
            ),
            width: 360,
            name: "voucher-statement"
        )
    }

    func testSettlementVoucherRenders() throws {
        let settlement = DailySettlement(
            dateKey: "2026-08-15",
            earnedToday: 545.45,
            elapsedPaidMinutes: 8 * 60,
            workdayMinutes: 8 * 60,
            progress: 1,
            sentiment: .heavy,
            streakDays: 14,
            headline: "今日窝囊费，全额到账",
            subCopy: "辛苦费按秒发放，一分没少。",
            bestMoment: "听完一场无关的会",
            cumulativeEarned: 23864.2,
            status: .done,
            capturedAt: Date(timeIntervalSince1970: 1_786_800_000)
        )

        try render(
            DailySettlementShareCard(
                settlement: settlement,
                displayedAmount: nil,
                displayedBestMoment: nil,
                hidesSensitiveInfo: false,
                showsControls: false
            ),
            width: 360,
            name: "voucher-settlement"
        )
    }
}
