import UIKit
import XCTest
@testable import Manhunt

final class AppSettingsTests: XCTestCase {
    @MainActor
    func testSettingsLinkOpensTheAppSettingsPage() {
        XCTAssertEqual(AppSettings.url?.absoluteString, UIApplication.openSettingsURLString)
    }
}
