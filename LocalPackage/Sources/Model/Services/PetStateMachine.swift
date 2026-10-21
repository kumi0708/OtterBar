/*
 PetStateMachine.swift
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

struct PetStateMachine: Sendable, Equatable {
    private(set) var state = PetState.play
    private(set) var generation = Int.zero
    private(set) var isSleeping = false
    private(set) var isBuilding = false
    private(set) var isAgentWorking = false
    private var oneShotStartedAt: Date?

    static let duplicateInterval: TimeInterval = 2.0

    var restingState: PetState {
        if isBuilding {
            .build
        } else if isAgentWorking {
            .work
        } else if isSleeping {
            .sleep
        } else {
            .play
        }
    }

    @discardableResult
    mutating func handle(_ event: PetEvent, at now: Date) -> PetState? {
        switch event {
        case .userIdle:
            isSleeping = true
            return settle()
        case .userReturned:
            guard isSleeping else { return nil }
            isSleeping = false
            return state == .sleep ? start(.wake, at: now) : settle()
        case .buildStarted:
            isBuilding = true
            return settle()
        case .buildSucceeded:
            isBuilding = false
            return start(.celebrate, at: now) ?? settle()
        case .buildFailed:
            isBuilding = false
            return start(.fail, at: now) ?? settle()
        case .agentStarted:
            isAgentWorking = true
            return settle()
        case .agentFinished:
            isAgentWorking = false
            return start(.wave, at: now) ?? settle()
        case let .randomAct(act):
            guard state == .play, act.isOneShot else { return nil }
            return start(act, at: now)
        case .longSession:
            guard state == .play else { return nil }
            return start(.drowsy, at: now)
        case let .oneShotFinished(finishedGeneration):
            guard finishedGeneration == generation, state.isOneShot else { return nil }
            return transition(to: restingState, at: now)
        }
    }

    private mutating func settle() -> PetState? {
        if state.isOneShot, state.rank <= restingState.rank {
            return nil
        }
        return transition(to: restingState, at: nil)
    }

    private mutating func start(_ oneShot: PetState, at now: Date) -> PetState? {
        guard oneShot.rank <= state.rank else { return nil }
        if oneShot == state, let oneShotStartedAt, now.timeIntervalSince(oneShotStartedAt) < Self.duplicateInterval {
            return nil
        }
        return transition(to: oneShot, at: now)
    }

    private mutating func transition(to newState: PetState, at now: Date?) -> PetState? {
        guard newState != state || newState.isOneShot else { return nil }
        state = newState
        generation += 1
        oneShotStartedAt = newState.isOneShot ? now : nil
        return newState
    }
}
