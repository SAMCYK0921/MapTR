//
//  VoiceService.swift
//  MTR Lift Guide
//
//  Spoken turn-by-turn guidance using AVSpeechSynthesizer, in one of
//  Cantonese / Mandarin / English selected from the More tab.
//

import AVFoundation
import Combine
import SwiftUI

/// Spoken guidance language.
enum VoiceLanguage: String, CaseIterable, Identifiable {
    case cantonese, mandarin, english

    var id: String { rawValue }

    var localeCode: String {
        switch self {
        case .cantonese: return "zh-HK"
        case .mandarin: return "zh-CN"
        case .english: return "en-GB"
        }
    }

    var displayZh: String {
        switch self {
        case .cantonese: return "粵語"
        case .mandarin: return "普通話"
        case .english: return "英語"
        }
    }

    var displayEn: String {
        switch self {
        case .cantonese: return "Cantonese"
        case .mandarin: return "Mandarin"
        case .english: return "English"
        }
    }
}

final class VoiceService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    static let voiceLanguageKey = "voiceLanguage"

    private let synthesizer = AVSpeechSynthesizer()
    @Published private(set) var isSpeaking = false

    /// Selected spoken language, persisted across launches.
    var language: VoiceLanguage {
        let stored = UserDefaults.standard.string(forKey: Self.voiceLanguageKey) ?? ""
        return VoiceLanguage(rawValue: stored) ?? .cantonese
    }

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("[Voice] audio session: \(error)")
        }
    }

    func speak(_ zh: String, _ en: String) {
        speakAll([(text(zh, en), language.localeCode)])
    }

    func speakRoute(_ waypoints: [Waypoint]) {
        let queue: [(String, String)] = waypoints.map { wp in
            (text(wp.titleZh + "。" + wp.descZh, wp.titleEn + ". " + wp.descEn), language.localeCode)
        }
        speakAll(queue)
    }

    /// Picks the phrasing for the currently selected spoken language.
    private func text(_ zh: String, _ en: String) -> String {
        language == .english ? en : zh
    }

    private func speakAll(_ items: [(String, String)]) {
        stop()
        for (text, language) in items {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: language)
                ?? AVSpeechSynthesisVoice(language: "en-GB")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
            utterance.postUtteranceDelay = 0.2
            synthesizer.speak(utterance)
        }
        isSpeaking = synthesizer.isSpeaking
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
}
