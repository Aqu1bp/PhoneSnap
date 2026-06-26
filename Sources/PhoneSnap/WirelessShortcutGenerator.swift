import Foundation

enum WirelessShortcutGenerator {
    enum GenerateError: LocalizedError {
        case templateEncodingFailed
        case plistConversionFailed(Error)
        case signingLaunchFailed(Error)
        case signingFailed(exitCode: Int32, stderr: String)
        case readBackFailed(Error)

        var errorDescription: String? {
            switch self {
            case .templateEncodingFailed:
                return "Could not encode the Shortcut template."
            case .plistConversionFailed(let error):
                return "Could not build the Shortcut file: \(error.localizedDescription)"
            case .signingLaunchFailed(let error):
                return "Could not run /usr/bin/shortcuts: \(error.localizedDescription)"
            case .signingFailed(let exitCode, let stderr):
                let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                if detail.isEmpty {
                    return "/usr/bin/shortcuts sign failed with exit code \(exitCode)."
                }
                return "/usr/bin/shortcuts sign failed with exit code \(exitCode): \(detail)"
            case .readBackFailed(let error):
                return "Could not read the signed Shortcut: \(error.localizedDescription)"
            }
        }
    }

    static func makeSigned(uploadURL: String, token: String, shortcutName: String = "PhoneSnap") throws -> Data {
        let waitUUID = UUID().uuidString
        let screenshotUUID = UUID().uuidString
        let uploadUUID = UUID().uuidString
        let xml = template
            .replacingOccurrences(of: "$$SHORTCUT_NAME$$", with: xmlEscape(shortcutName))
            .replacingOccurrences(of: "$$UPLOAD_URL$$", with: xmlEscape(uploadURL))
            .replacingOccurrences(of: "$$TOKEN$$", with: xmlEscape("Bearer \(token)"))
            .replacingOccurrences(of: "$$WAIT_UUID$$", with: waitUUID)
            .replacingOccurrences(of: "$$SCREENSHOT_UUID$$", with: screenshotUUID)
            .replacingOccurrences(of: "$$UPLOAD_UUID$$", with: uploadUUID)

        guard let xmlData = xml.data(using: .utf8) else {
            throw GenerateError.templateEncodingFailed
        }

        let plistObject: Any
        do {
            plistObject = try PropertyListSerialization.propertyList(from: xmlData, options: [], format: nil)
        } catch {
            throw GenerateError.plistConversionFailed(error)
        }

        let unsignedData: Data
        do {
            unsignedData = try PropertyListSerialization.data(
                fromPropertyList: plistObject,
                format: .binary,
                options: 0
            )
        } catch {
            throw GenerateError.plistConversionFailed(error)
        }

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let runID = UUID().uuidString
        let unsignedURL = tempDir.appendingPathComponent("PhoneSnap-unsigned-\(runID).shortcut")
        let signedURL = tempDir.appendingPathComponent("PhoneSnap-signed-\(runID).shortcut")
        defer {
            try? FileManager.default.removeItem(at: unsignedURL)
            try? FileManager.default.removeItem(at: signedURL)
        }

        try unsignedData.write(to: unsignedURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = [
            "sign",
            "--mode", "anyone",
            "--input", unsignedURL.path,
            "--output", signedURL.path
        ]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()
        do {
            try process.run()
        } catch {
            throw GenerateError.signingLaunchFailed(error)
        }
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stderrData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
            let stderr = String(data: stderrData, encoding: .utf8) ?? "<binary stderr>"
            throw GenerateError.signingFailed(exitCode: process.terminationStatus, stderr: stderr)
        }

        do {
            return try Data(contentsOf: signedURL)
        } catch {
            throw GenerateError.readBackFailed(error)
        }
    }

    private static func xmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

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
                <string>is.workflow.actions.delay</string>
                <key>WFWorkflowActionParameters</key>
                <dict>
                    <key>UUID</key>
                    <string>$$WAIT_UUID$$</string>
                    <key>WFDelayTime</key>
                    <integer>1</integer>
                </dict>
            </dict>
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
                    <string>$$UPLOAD_UUID$$</string>
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
                            <array>
                                <dict>
                                    <key>WFItemType</key>
                                    <integer>0</integer>
                                    <key>WFKey</key>
                                    <dict>
                                        <key>Value</key>
                                        <dict>
                                            <key>string</key>
                                            <string>Authorization</string>
                                        </dict>
                                        <key>WFSerializationType</key>
                                        <string>WFTextTokenString</string>
                                    </dict>
                                    <key>WFValue</key>
                                    <dict>
                                        <key>Value</key>
                                        <dict>
                                            <key>string</key>
                                            <string>$$TOKEN$$</string>
                                        </dict>
                                        <key>WFSerializationType</key>
                                        <string>WFTextTokenString</string>
                                    </dict>
                                </dict>
                            </array>
                        </dict>
                        <key>WFSerializationType</key>
                        <string>WFDictionaryFieldValue</string>
                    </dict>
                    <key>WFHTTPMethod</key>
                    <string>POST</string>
                    <key>WFURL</key>
                    <string>$$UPLOAD_URL$$</string>
                </dict>
            </dict>
        </array>
    </dict>
    </plist>
    """
}

