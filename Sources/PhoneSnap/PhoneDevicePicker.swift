import AppKit

@MainActor
enum PhoneDevicePicker {
    static func populate(_ picker: NSPopUpButton, phones: [PhoneDevice], selectedID: String?) {
        picker.removeAllItems()
        let titles = phones.map { "\($0.name) — \($0.isUSB ? "Cable" : "Wi-Fi")" }
        let menu = NSMenu()
        for (index, phone) in phones.enumerated() {
            var title = titles[index]
            let peers = phones.indices.filter { titles[$0] == title }.map { phones[$0].id }
            if peers.count > 1 {
                var length = min(6, phone.id.count)
                while length < phone.id.count && peers.filter({ $0.suffix(length) == phone.id.suffix(length) }).count > 1 { length += 1 }
                title += " (…\(phone.id.suffix(length)))"
            }
            // NSPopUpButton.addItem(withTitle:) coalesces duplicate titles. Menu
            // items retain one row per device; identity never depends on row index.
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = phone.id
            menu.addItem(item)
        }
        picker.menu = menu
        if let selected = menu.items.first(where: { ($0.representedObject as? String) == selectedID }) {
            picker.select(selected)
        } else if let first = menu.items.first { picker.select(first) }
    }

    static func selectedPhone(in picker: NSPopUpButton, phones: [PhoneDevice]) -> PhoneDevice? {
        guard let id = picker.selectedItem?.representedObject as? String else { return nil }
        return phones.first { $0.id == id }
    }
}
