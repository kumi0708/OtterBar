/*
 PetState.swift
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

public enum PetState: String, Sendable, CaseIterable, Identifiable {
    case play = "play"
    case sleep = "sleep"
    case wake = "wake"
    case build = "build"
    case celebrate = "celebrate"
    case fail = "fail"
    case faceWash = "face-wash"
    case lookAround = "look-around"
    case work = "work"
    case wave = "wave"
    case drowsy = "drowsy"

    public var id: String { rawValue }

    public var numberOfFrames: Int {
        switch self {
        case .play: 24
        case .sleep: 12
        case .wake: 12
        case .build: 12
        case .celebrate: 16
        case .fail: 18
        case .faceWash: 16
        case .lookAround: 14
        case .work: 12
        case .wave: 14
        case .drowsy: 16
        }
    }

    public var playback: PetPlayback {
        switch self {
        case .play: .loop(speed: nil)
        case .sleep: .loop(speed: 3.0)
        case .build: .loop(speed: 12.0)
        case .work: .loop(speed: 6.0)
        case .wake: .once(speed: 6.0)
        case .celebrate: .once(speed: 6.0)
        case .fail: .once(speed: 6.0)
        case .faceWash: .once(speed: 5.0)
        case .lookAround: .once(speed: 4.0)
        case .wave: .once(speed: 5.0)
        case .drowsy: .once(speed: 3.0)
        }
    }

    public var isOneShot: Bool {
        if case .once = playback { true } else { false }
    }

    public var rank: Int {
        switch self {
        case .celebrate, .fail: 0
        case .build, .work, .wave: 1
        case .sleep, .wake: 2
        case .drowsy: 3
        case .play, .faceWash, .lookAround: 4
        }
    }

    public static let cpuSpeedMultiplier: Float = 2.0
    public static let maximumCPULinkedSpeed: Float = 16.0

    public func speed(forRunnerSpeed runnerSpeed: Float) -> Float {
        playback.fixedSpeed ?? min(runnerSpeed * Self.cpuSpeedMultiplier, Self.maximumCPULinkedSpeed)
    }

    public var duration: Double? {
        guard case let .once(speed) = playback else { return nil }
        return Double(numberOfFrames) / (2.0 * Double(speed))
    }
}

public enum PetPlayback: Sendable, Equatable {
    case loop(speed: Float?)
    case once(speed: Float)

    public var repeats: Bool {
        if case .loop = self { true } else { false }
    }

    public var fixedSpeed: Float? {
        switch self {
        case let .loop(speed): speed
        case let .once(speed): speed
        }
    }
}
