/*
 PetService.swift
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
import Foundation

actor PetService {
    private let appStateClient: AppStateClient
    private let dateClient: DateClient
    private let darwinNotificationClient: DarwinNotificationClient
    private let idleTimeClient: IdleTimeClient
    private let logService: LogService
    private let userDefaultsRepository: UserDefaultsRepository
    private(set) var machine = PetStateMachine()
    private var activeSince: Date?
    private var lastLongSessionAt: Date?

    static let activityCheckInterval: Duration = .seconds(2)
    static let returnedThreshold: TimeInterval = 5.0
    static let breakThreshold: TimeInterval = 5.0 * 60.0
    static let longSessionThreshold: TimeInterval = 50.0 * 60.0
    static let longSessionReminderInterval: TimeInterval = 15.0 * 60.0
    static let randomActIntervals: ClosedRange<Double> = 60.0 ... 150.0
    static let randomActs: [PetState] = [.faceWash, .lookAround]

    init(_ appDependencies: AppDependencies) {
        appStateClient = appDependencies.appStateClient
        dateClient = appDependencies.dateClient
        darwinNotificationClient = appDependencies.darwinNotificationClient
        idleTimeClient = appDependencies.idleTimeClient
        logService = .init(appDependencies)
        userDefaultsRepository = .init(appDependencies.userDefaultsClient)
    }

    func run() async {
        appStateClient.send(\.petStates, machine.state)
        await withTaskGroup { group in
            group.addTask { await self.observeNotifications() }
            group.addTask { await self.observeActivity() }
            group.addTask { await self.performRandomActs() }
        }
    }

    func handle(_ event: PetEvent) {
        guard let newState = machine.handle(event, at: dateClient.now()) else { return }
        appStateClient.send(\.petStates, newState)
        logService.notice(.petStateChanged(newState))
        guard let duration = newState.duration else { return }
        let generation = machine.generation
        Task {
            try? await Task.sleep(for: .seconds(duration))
            self.handle(.oneShotFinished(generation: generation))
        }
    }

    func handle(notificationName: String) {
        guard userDefaultsRepository.petReactsToEvents,
              let event = PetEvent(notificationName: notificationName) else {
            return
        }
        handle(event)
    }

    func checkActivity() {
        let idleSeconds = idleTimeClient.secondsSinceLastInput()
        let now = dateClient.now()
        let idleThreshold = TimeInterval(userDefaultsRepository.petIdleMinutes) * 60.0
        if !userDefaultsRepository.petReactsToIdle || idleSeconds < Self.returnedThreshold {
            if machine.isSleeping {
                handle(.userReturned)
            }
        } else if !machine.isSleeping, idleSeconds >= idleThreshold {
            handle(.userIdle)
        }
        if idleSeconds >= Self.breakThreshold {
            activeSince = nil
        } else if activeSince == nil {
            activeSince = now.addingTimeInterval(-idleSeconds)
        }
        guard let activeSince, now.timeIntervalSince(activeSince) >= Self.longSessionThreshold else {
            return
        }
        if let lastLongSessionAt, now.timeIntervalSince(lastLongSessionAt) < Self.longSessionReminderInterval {
            return
        }
        lastLongSessionAt = now
        handle(.longSession)
    }

    private func observeNotifications() async {
        let names = Array(PetEvent.notificationNames.keys)
        for await name in darwinNotificationClient.stream(names) {
            handle(notificationName: name)
        }
    }

    private func observeActivity() async {
        while !Task.isCancelled {
            checkActivity()
            try? await Task.sleep(for: Self.activityCheckInterval)
        }
    }

    private func performRandomActs() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: Self.randomActIntervals)))
            guard userDefaultsRepository.petRandomActs,
                  let act = Self.randomActs.randomElement() else {
                continue
            }
            handle(.randomAct(act))
        }
    }
}
