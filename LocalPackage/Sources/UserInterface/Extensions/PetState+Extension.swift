/*
 PetState+Extension.swift
 UserInterface

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

extension PetState {
    var localizedName: String {
        switch self {
        case .play: String(localized: "petState.play", bundle: .module)
        case .sleep: String(localized: "petState.sleep", bundle: .module)
        case .wake: String(localized: "petState.wake", bundle: .module)
        case .build: String(localized: "petState.build", bundle: .module)
        case .celebrate: String(localized: "petState.celebrate", bundle: .module)
        case .fail: String(localized: "petState.fail", bundle: .module)
        case .faceWash: String(localized: "petState.faceWash", bundle: .module)
        case .lookAround: String(localized: "petState.lookAround", bundle: .module)
        case .work: String(localized: "petState.work", bundle: .module)
        case .wave: String(localized: "petState.wave", bundle: .module)
        case .drowsy: String(localized: "petState.drowsy", bundle: .module)
        }
    }
}

extension PetEvent {
    var localizedName: String {
        switch self {
        case .buildStarted: String(localized: "petEvent.buildStarted", bundle: .module)
        case .buildSucceeded: String(localized: "petEvent.buildSucceeded", bundle: .module)
        case .buildFailed: String(localized: "petEvent.buildFailed", bundle: .module)
        case .agentStarted: String(localized: "petEvent.agentStarted", bundle: .module)
        case .agentFinished: String(localized: "petEvent.agentFinished", bundle: .module)
        case .userIdle, .userReturned, .randomAct, .longSession, .oneShotFinished: ""
        }
    }
}
