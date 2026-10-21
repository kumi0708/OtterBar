import AllocatedUnfairLock
import Foundation
import Testing

@testable import DataSource
@testable import Model

struct PetServiceTests {
    private func makeSUT(
        appState: AllocatedUnfairLock<AppState>,
        idleSeconds: AllocatedUnfairLock<TimeInterval>,
        now: AllocatedUnfairLock<Date> = .init(initialState: Date(timeIntervalSince1970: 0)),
        flags: [String: Bool] = [:]
    ) -> PetService {
        PetService(.testDependencies(
            appStateClient: .testDependency(appState),
            dateClient: testDependency(of: DateClient.self) {
                $0.now = { now.withLock(\.self) }
            },
            idleTimeClient: testDependency(of: IdleTimeClient.self) {
                $0.secondsSinceLastInput = { idleSeconds.withLock(\.self) }
            },
            userDefaultsClient: testDependency(of: UserDefaultsClient.self) {
                let values = [
                    "PET_REACTS_TO_IDLE": true,
                    "PET_REACTS_TO_EVENTS": true,
                ].merging(flags) { $1 }
                $0.bool = { values[$0] ?? false }
                $0.integer = { $0 == "PET_IDLE_MINUTES" ? 5 : 0 }
            }
        ))
    }

    @Test
    func checkActivity_sends_sleep_after_idle_threshold_and_wake_on_return() async {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let idleSeconds = AllocatedUnfairLock<TimeInterval>(initialState: 299)
        let sut = makeSUT(appState: appState, idleSeconds: idleSeconds)
        await sut.checkActivity()
        #expect(appState.withLock(\.petStates.latestValue) == nil)
        idleSeconds.withLock { $0 = 300 }
        await sut.checkActivity()
        #expect(appState.withLock(\.petStates.latestValue) == .sleep)
        idleSeconds.withLock { $0 = 1 }
        await sut.checkActivity()
        #expect(appState.withLock(\.petStates.latestValue) == .wake)
    }

    @Test
    func checkActivity_does_not_sleep_when_idle_reaction_is_disabled() async {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let idleSeconds = AllocatedUnfairLock<TimeInterval>(initialState: 3_600)
        let sut = makeSUT(appState: appState, idleSeconds: idleSeconds, flags: ["PET_REACTS_TO_IDLE": false])
        await sut.checkActivity()
        #expect(appState.withLock(\.petStates.latestValue) == nil)
    }

    @Test
    func checkActivity_sends_drowsy_after_long_session_once_per_reminder_interval() async {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let idleSeconds = AllocatedUnfairLock<TimeInterval>(initialState: 1)
        let now = AllocatedUnfairLock<Date>(initialState: Date(timeIntervalSince1970: 0))
        let sut = makeSUT(appState: appState, idleSeconds: idleSeconds, now: now)
        await sut.checkActivity()
        now.withLock { $0 = Date(timeIntervalSince1970: 50 * 60) }
        await sut.checkActivity()
        #expect(appState.withLock(\.petStates.latestValue) == .drowsy)
        await sut.handle(.oneShotFinished(generation: sut.machine.generation))
        now.withLock { $0 = Date(timeIntervalSince1970: 55 * 60) }
        await sut.checkActivity()
        #expect(appState.withLock(\.petStates.latestValue) == .play)
    }

    @Test
    func handle_notificationName_maps_to_event() async {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let sut = makeSUT(appState: appState, idleSeconds: .init(initialState: 0))
        await sut.handle(notificationName: "com.otterbar.build.started")
        #expect(appState.withLock(\.petStates.latestValue) == .build)
        await sut.handle(notificationName: "com.otterbar.unknown")
        #expect(appState.withLock(\.petStates.latestValue) == .build)
    }

    @Test
    func handle_notificationName_is_ignored_when_events_are_disabled() async {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let sut = makeSUT(appState: appState, idleSeconds: .init(initialState: 0), flags: ["PET_REACTS_TO_EVENTS": false])
        await sut.handle(notificationName: "com.otterbar.build.failed")
        #expect(appState.withLock(\.petStates.latestValue) == nil)
    }

    @Test
    func handle_one_shot_returns_to_resting_state_after_its_duration() async {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let sut = makeSUT(appState: appState, idleSeconds: .init(initialState: 0))
        await sut.handle(.randomAct(.lookAround))
        #expect(appState.withLock(\.petStates.latestValue) == .lookAround)
        try? await Task.sleep(for: .seconds(PetState.lookAround.duration! + 0.3))
        #expect(appState.withLock(\.petStates.latestValue) == .play)
    }
}
