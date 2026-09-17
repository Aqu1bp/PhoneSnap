import XCTest
@testable import PhoneSnap

final class WirelessShortcutGeneratorTests: XCTestCase {
    func testCaptureHeaderUsesEachPhotosDateTakenWithISOTime() throws {
        let uploadURL = "http://localhost:18472/api/v1/upload/test-pair"
        let data = try WirelessShortcutGenerator.makeUnsigned(uploadURL: uploadURL, token: "test-token")
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let actions = try XCTUnwrap(plist["WFWorkflowActions"] as? [[String: Any]])
        XCTAssertEqual(actions.compactMap { $0["WFWorkflowActionIdentifier"] as? String }, [
            "is.workflow.actions.delay", "is.workflow.actions.getlastscreenshot",
            "is.workflow.actions.repeat.each", "is.workflow.actions.downloadurl", "is.workflow.actions.repeat.each"
        ])
        let selection = try XCTUnwrap(actions[1]["WFWorkflowActionParameters"] as? [String: Any])
        XCTAssertEqual(selection["WFGetLatestPhotoCount"] as? Int, 10)
        let upload = try XCTUnwrap(actions[3]["WFWorkflowActionParameters"] as? [String: Any])
        XCTAssertEqual(upload["WFURL"] as? String, uploadURL)
        XCTAssertEqual(upload["WFHTTPMethod"] as? String, "POST")
        let fields = try XCTUnwrap((upload["WFHTTPHeaders"] as? NSDictionary)?["Value"] as? NSDictionary)
        let headers = try XCTUnwrap(fields["WFDictionaryFieldValueItems"] as? [NSDictionary])
        func value(for key: String) throws -> NSDictionary {
            let field = try XCTUnwrap(headers.first { (($0["WFKey"] as? NSDictionary)?["Value"] as? NSDictionary)?["string"] as? String == key })
            return try XCTUnwrap((field["WFValue"] as? NSDictionary)?["Value"] as? NSDictionary)
        }
        XCTAssertEqual(try value(for: "Authorization")["string"] as? String, "Bearer test-token")
        let capture = try value(for: "X-PhoneSnap-Captured-At")
        XCTAssertEqual(capture["string"] as? String, "\u{fffc}")
        let token = try XCTUnwrap((capture["attachmentsByRange"] as? NSDictionary)?["{0, 1}"] as? NSDictionary)
        XCTAssertEqual(token["Type"] as? String, "Variable")
        XCTAssertEqual(token["VariableName"] as? String, "Repeat Item")
        let conversions = try XCTUnwrap(token["Aggrandizements"] as? [NSDictionary])
        XCTAssertEqual(conversions.count, 2)
        XCTAssertEqual(conversions[0]["Type"] as? String, "WFPropertyVariableAggrandizement")
        XCTAssertEqual(conversions[0]["PropertyName"] as? String, "Date Taken")
        XCTAssertEqual(conversions[1]["Type"] as? String, "WFDateFormatVariableAggrandizement")
        XCTAssertEqual(conversions[1]["WFDateFormatStyle"] as? String, "Custom")
        XCTAssertEqual(conversions[1]["WFDateFormat"] as? String, "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX")
    }
}
