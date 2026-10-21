/*
 PetSettings.swift
 Model

 Created by OtterBar contributors on 2026/10/18.
 Modified from RunCat Neo, Copyright 2026 Kyome22 (Takuto Nakamura)

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

import DataSource
import Observation

@MainActor @Observable
public final class PetSettings: Composable {
    private let appStateClient: AppStateClient
    private let darwinNotificationClient: DarwinNotificationClient
    private let userDefaultsRepository: UserDefaultsRepository

    public var currentState: PetState
    public var reactsToIdle: Bool
    public var idleMinutes: Int
    public var reactsToEvents: Bool
    public var randomActs: Bool
    public let action: (Action) async -> Void

    public static let idleMinutesRange = 1 ... 60
    public static let trialEvents: [PetEvent] = [
        .buildStarted,
        .buildSucceeded,
        .buildFailed,
        .agentStarted,
        .agentFinished,
    ]

    public init(
        _ appDependencies: AppDependencies,
        action: @escaping (Action) async -> Void = { _ in }
    ) {
        self.appStateClient = appDependencies.appStateClient
        self.darwinNotificationClient = appDependencies.darwinNotificationClient
        self.userDefaultsRepository = .init(appDependencies.userDefaultsClient)
        self.currentState = appStateClient.withLock(\.petStates.latestValue) ?? .play
        self.reactsToIdle = userDefaultsRepository.petReactsToIdle
        self.idleMinutes = userDefaultsRepository.petIdleMinutes
        self.reactsToEvents = userDefaultsRepository.petReactsToEvents
        self.randomActs = userDefaultsRepository.petRandomActs
        self.action = action
    }

    public func reduce(_ action: Action) async {
        switch action {
        case .task:
            let stream = appStateClient.withLock(\.petStates.stream)
            for await value in stream {
                currentState = value
            }

        case let .reactsToIdleToggleSwitched(isOn):
            reactsToIdle = isOn
            userDefaultsRepository.petReactsToIdle = isOn

        case let .idleMinutesChanged(minutes):
            idleMinutes = min(max(minutes, Self.idleMinutesRange.lowerBound), Self.idleMinutesRange.upperBound)
            userDefaultsRepository.petIdleMinutes = idleMinutes

        case let .reactsToEventsToggleSwitched(isOn):
            reactsToEvents = isOn
            userDefaultsRepository.petReactsToEvents = isOn

        case let .randomActsToggleSwitched(isOn):
            randomActs = isOn
            userDefaultsRepository.petRandomActs = isOn

        case let .trialButtonTapped(event):
            guard let name = PetEvent.notificationNames.first(where: { $0.value == event })?.key else {
                return
            }
            darwinNotificationClient.post(name)
        }
    }

    public enum Action: Sendable {
        case task
        case reactsToIdleToggleSwitched(Bool)
        case idleMinutesChanged(Int)
        case reactsToEventsToggleSwitched(Bool)
        case randomActsToggleSwitched(Bool)
        case trialButtonTapped(PetEvent)
    }
}
