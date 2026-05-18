import Foundation

/// Generates a signed `.shortcut` file pre-configured with this Mac's
/// HTTP receiver URL. The signed file imports on any iPhone via
/// `shortcuts://import-shortcut?url=...` without requiring the
/// "Allow Untrusted Shortcuts" toggle, because the macOS `shortcuts sign
/// --mode anyone` CLI produces the same trust scope Apple uses for
/// iCloud-shared Shortcuts.
///
/// Pipeline:
/// 1. Take a constant XML template + the Mac's target URL
/// 2. Substitute the URL into the template
/// 3. Convert XML → binary plist via PropertyListSerialization
/// 4. Write to a temp file
/// 5. Invoke `/usr/bin/shortcuts sign --mode anyone --input ... --output ...`
/// 6. Read back the signed bytes and return them
///
/// Each call yields a fresh signed file with the current URL baked in.
enum ShortcutGenerator {
    enum GenerateError: Error {
        case templateSerializationFailed
        case binaryConversionFailed(Error)
        case signingFailed(exitCode: Int32, stderr: String)
        case readBackFailed(Error)
    }

    /// Returns the signed `.shortcut` bytes ready to serve to a browser
    /// that's been pointed at us by `shortcuts://import-shortcut?url=…`.
    static func makeSigned(macURL: String, shortcutName: String = "Send Screenshot To Mac") throws -> Data {
        // Random UUIDs for action linking so two shortcuts generated in the
        // same Mac session don't collide if imported back-to-back.
        let screenshotActionUUID = UUID().uuidString
        let downloadActionUUID = UUID().uuidString
        let xml = template
            .replacingOccurrences(of: "$$MAC_URL$$", with: xmlEscape(macURL))
            .replacingOccurrences(of: "$$SHORTCUT_NAME$$", with: xmlEscape(shortcutName))
            .replacingOccurrences(of: "$$SCREENSHOT_UUID$$", with: screenshotActionUUID)
            .replacingOccurrences(of: "$$DOWNLOAD_UUID$$", with: downloadActionUUID)

        // Parse XML to dict, re-serialize as binary plist (Shortcuts on iOS
        // expects binary format).
        guard let xmlData = xml.data(using: .utf8) else {
            throw GenerateError.templateSerializationFailed
        }
        let plistObject: Any
        do {
            plistObject = try PropertyListSerialization.propertyList(from: xmlData, options: [], format: nil)
        } catch {
            throw GenerateError.binaryConversionFailed(error)
        }
        let unsignedBin: Data
        do {
            unsignedBin = try PropertyListSerialization.data(
                fromPropertyList: plistObject,
                format: .binary,
                options: 0
            )
        } catch {
            throw GenerateError.binaryConversionFailed(error)
        }

        // Write unsigned bytes to a temp file, sign via the `shortcuts` CLI.
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let runID = UUID().uuidString
        let unsignedURL = tmpDir.appendingPathComponent("ScreenshotCatch-unsigned-\(runID).shortcut")
        let signedURL = tmpDir.appendingPathComponent("ScreenshotCatch-signed-\(runID).shortcut")
        defer {
            try? FileManager.default.removeItem(at: unsignedURL)
            try? FileManager.default.removeItem(at: signedURL)
        }
        try unsignedBin.write(to: unsignedURL)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        proc.arguments = [
            "sign",
            "--mode", "anyone",
            "--input", unsignedURL.path,
            "--output", signedURL.path
        ]
        let stderrPipe = Pipe()
        proc.standardError = stderrPipe
        proc.standardOutput = Pipe()  // discard stdout
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let stderrData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
            let stderrStr = String(data: stderrData, encoding: .utf8) ?? "<binary>"
            throw GenerateError.signingFailed(exitCode: proc.terminationStatus, stderr: stderrStr)
        }
        do {
            return try Data(contentsOf: signedURL)
        } catch {
            throw GenerateError.readBackFailed(error)
        }
    }

    // MARK: helpers
    private static func xmlEscape(_ s: String) -> String {
        s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// XML template of a complete unsigned Shortcut, with placeholders for
    /// the target URL and shortcut name. Action structure verified against
    /// a hand-authored "Send Screenshot to Mac" shortcut extracted from
    /// ~/Library/Shortcuts/Shortcuts.sqlite.
    private static let template = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>WFWorkflowClientVersion</key>
        <string>2607.0.6</string>
        <key>WFWorkflowMinimumClientVersion</key>
        <integer>900</integer>
        <key>WFWorkflowName</key>
        <string>$$SHORTCUT_NAME$$</string>
        <key>WFWorkflowIcon</key>
        <dict>
            <key>WFWorkflowIconStartColor</key>
            <integer>463140863</integer>
            <key>WFWorkflowIconGlyphNumber</key>
            <integer>59511</integer>
        </dict>
        <key>WFWorkflowInputContentItemClasses</key>
        <array>
            <string>WFAppStoreAppContentItem</string>
            <string>WFArticleContentItem</string>
            <string>WFContactContentItem</string>
            <string>WFDateContentItem</string>
            <string>WFEmailAddressContentItem</string>
            <string>WFGenericFileContentItem</string>
            <string>WFImageContentItem</string>
            <string>WFiTunesProductContentItem</string>
            <string>WFLocationContentItem</string>
            <string>WFDictionaryContentItem</string>
            <string>WFMKMapItemContentItem</string>
            <string>WFNumberContentItem</string>
            <string>WFPDFContentItem</string>
            <string>WFPhoneNumberContentItem</string>
            <string>WFRichTextContentItem</string>
            <string>WFSafariWebPageContentItem</string>
            <string>WFStringContentItem</string>
            <string>WFURLContentItem</string>
        </array>
        <key>WFWorkflowTypes</key>
        <array>
            <string>NCWidget</string>
            <string>WatchKit</string>
        </array>
        <key>WFWorkflowImportQuestions</key>
        <array/>
        <key>WFWorkflowActions</key>
        <array>
            <dict>
                <key>WFWorkflowActionIdentifier</key>
                <string>is.workflow.actions.getlastscreenshot</string>
                <key>WFWorkflowActionParameters</key>
                <dict>
                    <key>UUID</key>
                    <string>$$SCREENSHOT_UUID$$</string>
                    <key>WFGetLatestPhotoCount</key>
                    <integer>1</integer>
                </dict>
            </dict>
            <dict>
                <key>WFWorkflowActionIdentifier</key>
                <string>is.workflow.actions.downloadurl</string>
                <key>WFWorkflowActionParameters</key>
                <dict>
                    <key>ShowHeaders</key>
                    <true/>
                    <key>UUID</key>
                    <string>$$DOWNLOAD_UUID$$</string>
                    <key>WFFormValues</key>
                    <dict>
                        <key>Value</key>
                        <dict>
                            <key>WFDictionaryFieldValueItems</key>
                            <array>
                                <dict>
                                    <key>WFItemType</key>
                                    <integer>5</integer>
                                    <key>WFKey</key>
                                    <dict>
                                        <key>Value</key>
                                        <dict>
                                            <key>string</key>
                                            <string>file</string>
                                        </dict>
                                        <key>WFSerializationType</key>
                                        <string>WFTextTokenString</string>
                                    </dict>
                                    <key>WFValue</key>
                                    <dict>
                                        <key>Value</key>
                                        <dict>
                                            <key>Value</key>
                                            <dict>
                                                <key>OutputName</key>
                                                <string>Latest Screenshots</string>
                                                <key>OutputUUID</key>
                                                <string>$$SCREENSHOT_UUID$$</string>
                                                <key>Type</key>
                                                <string>ActionOutput</string>
                                            </dict>
                                            <key>WFSerializationType</key>
                                            <string>WFTextTokenAttachment</string>
                                        </dict>
                                        <key>WFSerializationType</key>
                                        <string>WFTokenAttachmentParameterState</string>
                                    </dict>
                                </dict>
                            </array>
                        </dict>
                        <key>WFSerializationType</key>
                        <string>WFDictionaryFieldValue</string>
                    </dict>
                    <key>WFHTTPBodyType</key>
                    <string>Form</string>
                    <key>WFHTTPHeaders</key>
                    <dict>
                        <key>Value</key>
                        <dict>
                            <key>WFDictionaryFieldValueItems</key>
                            <array/>
                        </dict>
                        <key>WFSerializationType</key>
                        <string>WFDictionaryFieldValue</string>
                    </dict>
                    <key>WFHTTPMethod</key>
                    <string>POST</string>
                    <key>WFURL</key>
                    <string>$$MAC_URL$$</string>
                </dict>
            </dict>
        </array>
    </dict>
    </plist>
    """
}
