//
//  L10n.swift
//  MTR Lift Guide
//
//  In-app language switch (中文 / English), persisted across launches.
//

import Foundation
import SwiftUI

final class Lang: ObservableObject {

    enum Code: String {
        case zh
        case en
    }

    @Published var code: Code {
        didSet {
            UserDefaults.standard.set(code.rawValue, forKey: "app.lang")
        }
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: "app.lang"),
           let saved = Code(rawValue: saved) {
            code = saved
        } else {
            code = Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .zh : .en
        }
    }

    func t(_ zh: String, _ en: String) -> String {
        code == .zh ? zh : en
    }

    var toggleLabel: String { code == .zh ? "EN" : "中" }

    var isChinese: Bool { code == .zh }
}
