import AllocatedUnfairLock
import Foundation
import Testing

@testable import DataSource
@testable import Model

struct PetSettingsTests {
    @MainActor @Test
    func send_reactsToIdleToggleSwitched_updates_state_and_user_defaults() async {
        let setCallStack = AllocatedUnfairLock<[String]>(initialState: [])
        let sut = PetSettings(.testDependencies(
            userDefaultsClient: testDependency(of: UserDefaultsClient.self) {
                $0.set = { value, key in
                    let entry = "set: \(key) = \(value ?? "nil")"
                    setCallStack.withLock { $0.append(entry) }
                }
            }
        ))
        await sut.send(.reactsToIdleToggleSwitched(true))
        #expect(sut.reactsToIdle)
        #expect(setCallStack.withLock(\.self) == ["set: PET_REACTS_TO_IDLE = true"])
    }

    @MainActor @Test
    func send_idleMinutesChanged_clamps_value_to_range() async {
        let sut = PetSettings(.testDependencies())
        await sut.send(.idleMinutesChanged(120))
        #expect(sut.idleMinutes == 60)
        await sut.send(.idleMinutesChanged(0))
        #expect(sut.idleMinutes == 1)
    }

    @MainActor @Test
    func send_trialButtonTapped_posts_darwin_notification() async {
        let posted = AllocatedUnfairLock<[String]>(initialState: [])
        let sut = PetSettings(.testDependencies(
            darwinNotificationClient: testDependency(of: DarwinNotificationClient.self) {
                $0.post = { name in posted.withLock { $0.append(name) } }
            }
        ))
        await sut.send(.trialButtonTapped(.buildFailed))
        #expect(posted.withLock(\.self) == ["com.otterbar.build.failed"])
    }

    @MainActor @Test
    func send_task_tracks_current_pet_state() async {
        let appState = AllocatedUnfairLock<AppState>(initialState: .init())
        let sut = PetSettings(.testDependencies(appStateClient: .testDependency(appState)))
        let task = Task { await sut.send(.task) }
        appState.withLock { $0.petStates.send(.sleep) }
        await waitUntil { sut.currentState == .sleep }
        #expect(sut.currentState == .sleep)
        task.cancel()
    }
}
