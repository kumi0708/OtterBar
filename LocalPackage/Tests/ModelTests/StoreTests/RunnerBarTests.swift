import AllocatedUnfairLock
import AppKit
import Foundation
import Testing

@testable import DataSource
@testable import Model

struct RunnerBarTests {
    private func makeEventBridge(recording callStack: AllocatedUnfairLock<[String]>) -> RunnerBar.Action.EventBridge {
        RunnerBar.Action.EventBridge(
            getBundleImage: { name in
                callStack.withLock { $0.append("getBundleImage: \(name)") }
                return NSImage(size: CGSize(width: 10, height: 18))
            },
            setSize: { size in
                callStack.withLock { $0.append("setSize: \(size.width)x\(size.height)") }
            },
            setFrames: { images, isTemplate, repeats in
                callStack.withLock { $0.append("setFrames: \(images.count), \(isTemplate), \(repeats)") }
            },
            setColor: { _, _ in },
            setSpeed: { speed in
                callStack.withLock { $0.append("setSpeed: \(speed)") }
            }
        )
    }

    @MainActor @Test
    func send_viewAppeared_applies_latest_runner_bundle_to_event_bridge() async {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        appState.withLock {
            $0.runnerBundles.send(RunnerBundle(
                runner: .default,
                frames: [.preset("cat-frame-0"), .preset("cat-frame-1")]
            ))
        }
        let callStack = AllocatedUnfairLock<[String]>(initialState: [])
        let sut = RunnerBar(.testDependencies(appStateClient: .testDependency(appState)))
        await sut.send(.viewAppeared("RunnerBarTests", makeEventBridge(recording: callStack)))
        await waitUntil { callStack.withLock(\.self).count >= 4 }
        #expect(sut.isReady)
        #expect(sut.size == CGSize(width: 10, height: 18))
        #expect(sut.isTemplate)
        #expect(callStack.withLock(\.self) == [
            "getBundleImage: cat-frame-0",
            "getBundleImage: cat-frame-1",
            "setSize: 10.0x18.0",
            "setFrames: 2, true, true",
        ])
        await sut.send(.viewDisappeared)
    }

    @MainActor @Test
    func send_viewAppeared_applies_runner_speed_to_event_bridge() async {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        appState.withLock { $0.runnerSpeeds.send(12.5) }
        let callStack = AllocatedUnfairLock<[String]>(initialState: [])
        let sut = RunnerBar(.testDependencies(appStateClient: .testDependency(appState)))
        await sut.send(.viewAppeared("RunnerBarTests", makeEventBridge(recording: callStack)))
        await waitUntil { !callStack.withLock(\.self).isEmpty }
        #expect(callStack.withLock(\.self) == ["setSpeed: 12.5"])
        await sut.send(.viewDisappeared)
    }

    @MainActor @Test
    func send_viewAppeared_ignores_thumbnail_bundle() async {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        appState.withLock {
            $0.runnerBundles.send(RunnerBundle(runner: .default, frame: .preset("cat-frame-0")))
        }
        let callStack = AllocatedUnfairLock<[String]>(initialState: [])
        let sut = RunnerBar(.testDependencies(appStateClient: .testDependency(appState)))
        await sut.send(.viewAppeared("RunnerBarTests", makeEventBridge(recording: callStack)))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(callStack.withLock(\.self).isEmpty)
        #expect(sut.icon == nil)
        await sut.send(.viewDisappeared)
    }

    @MainActor @Test
    func send_viewAppeared_with_broken_frames_clears_icon() async {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        appState.withLock {
            $0.runnerBundles.send(RunnerBundle(runner: .default, frames: [.broken]))
        }
        let callStack = AllocatedUnfairLock<[String]>(initialState: [])
        let sut = RunnerBar(.testDependencies(appStateClient: .testDependency(appState)))
        await sut.send(.viewAppeared("RunnerBarTests", makeEventBridge(recording: callStack)))
        await waitUntil { callStack.withLock(\.self).count >= 2 }
        #expect(sut.icon == nil)
        #expect(sut.size == .zero)
        #expect(callStack.withLock(\.self) == [
            "setSize: 0.0x0.0",
            "setFrames: 0, true, true",
        ])
        await sut.send(.viewDisappeared)
    }

    @MainActor @Test
    func send_viewDisappeared_stops_observing_streams() async {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let callStack = AllocatedUnfairLock<[String]>(initialState: [])
        let sut = RunnerBar(.testDependencies(appStateClient: .testDependency(appState)))
        await sut.send(.viewAppeared("RunnerBarTests", makeEventBridge(recording: callStack)))
        await sut.send(.viewDisappeared)
        appState.withLock { $0.runnerSpeeds.send(5.0) }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(callStack.withLock(\.self).isEmpty)
    }
    @MainActor @Test
    func send_viewAppeared_plays_pet_reaction_once_at_fixed_speed_and_restores_cpu_speed() async {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        appState.withLock {
            $0.runnerBundles.send(RunnerBundle(runner: Runner(kind: .otter), frames: [.preset("otter-frame-0")]))
            $0.runnerSpeeds.send(2.5)
        }
        let callStack = AllocatedUnfairLock<[String]>(initialState: [])
        let sut = RunnerBar(.testDependencies(appStateClient: .testDependency(appState)))
        await sut.send(.viewAppeared("RunnerBarTests", makeEventBridge(recording: callStack)))
        await waitUntil { callStack.withLock(\.self).contains("setSpeed: 5.0") }
        callStack.withLock { $0.removeAll() }
        appState.withLock { $0.petStates.send(.celebrate) }
        await waitUntil { callStack.withLock(\.self).count >= 18 }
        #expect(callStack.withLock(\.self) == (0 ..< 16).map { "getBundleImage: otter-celebrate-frame-\($0)" } + [
            "setFrames: 16, true, false",
            "setSpeed: 6.0",
        ])
        callStack.withLock { $0.removeAll() }
        appState.withLock { $0.runnerSpeeds.send(7.0) }
        appState.withLock { $0.petStates.send(.play) }
        await waitUntil { callStack.withLock(\.self).count >= 26 }
        #expect(callStack.withLock(\.self) == (0 ..< 24).map { "getBundleImage: otter-frame-\($0)" } + [
            "setFrames: 24, true, true",
            "setSpeed: 14.0",
        ])
        await sut.send(.viewDisappeared)
    }

    @MainActor @Test
    func send_viewAppeared_ignores_pet_states_for_non_pet_runner() async {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        appState.withLock {
            $0.runnerBundles.send(RunnerBundle(runner: Runner(kind: .cat), frames: [.preset("cat-frame-0")]))
        }
        let callStack = AllocatedUnfairLock<[String]>(initialState: [])
        let sut = RunnerBar(.testDependencies(appStateClient: .testDependency(appState)))
        await sut.send(.viewAppeared("RunnerBarTests", makeEventBridge(recording: callStack)))
        await waitUntil { callStack.withLock(\.self).count >= 3 }
        callStack.withLock { $0.removeAll() }
        appState.withLock { $0.petStates.send(.fail) }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(callStack.withLock(\.self).isEmpty)
        await sut.send(.viewDisappeared)
    }
}

