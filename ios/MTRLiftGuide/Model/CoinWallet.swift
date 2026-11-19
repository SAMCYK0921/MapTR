//
//  CoinWallet.swift
//  MTR Lift Guide
//
//  Persistent coin balance. Coins come from walking the AR trail in game mode
//  and from actually helping someone on the station help board; the balance is
//  shown on the Recent tab.
//

import Foundation
import SwiftUI

final class CoinWallet: ObservableObject {

    /// Coins granted for completing one station-help request.
    static let helpReward = 500

    @Published private(set) var total: Int {
        didSet { persist() }
    }

    /// How many people the user has helped through the board.
    @Published private(set) var peopleHelped: Int {
        didSet { persist() }
    }

    private let defaults: UserDefaults
    private static let totalKey = "coins.total"
    private static let helpedKey = "coins.peopleHelped"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        total = max(0, defaults.integer(forKey: Self.totalKey))
        peopleHelped = max(0, defaults.integer(forKey: Self.helpedKey))
    }

    func add(_ amount: Int) {
        guard amount > 0 else { return }
        total += amount
    }

    /// Called when a help request is marked as helped.
    func rewardForHelping() {
        peopleHelped += 1
        total += Self.helpReward
    }

    func reset() {
        total = 0
        peopleHelped = 0
    }

    private func persist() {
        defaults.set(total, forKey: Self.totalKey)
        defaults.set(peopleHelped, forKey: Self.helpedKey)
    }
}
