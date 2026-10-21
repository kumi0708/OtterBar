/*
 PetEvent.swift
 DataSource

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

public enum PetEvent: Sendable, Hashable {
    case userIdle
    case userReturned
    case buildStarted
    case buildSucceeded
    case buildFailed
    case agentStarted
    case agentFinished
    case randomAct(PetState)
    case longSession
    case oneShotFinished(generation: Int)

    public static let notificationNames: [String: PetEvent] = [
        "com.otterbar.build.started": .buildStarted,
        "com.otterbar.build.succeeded": .buildSucceeded,
        "com.otterbar.build.failed": .buildFailed,
        "com.otterbar.agent.started": .agentStarted,
        "com.otterbar.agent.finished": .agentFinished,
    ]

    public init?(notificationName: String) {
        guard let event = Self.notificationNames[notificationName] else { return nil }
        self = event
    }
}
