import DataSource
import Foundation
import Testing

@testable import Model

struct PetStateMachineTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    @Test
    func handle_userIdle_from_play_transitions_to_sleep() {
        var sut = PetStateMachine()
        #expect(sut.handle(.userIdle, at: now) == .sleep)
        #expect(sut.isSleeping)
    }

    @Test
    func handle_userReturned_while_sleeping_plays_wake_then_returns_to_play() {
        var sut = PetStateMachine()
        sut.handle(.userIdle, at: now)
        #expect(sut.handle(.userReturned, at: now) == .wake)
        #expect(sut.handle(.oneShotFinished(generation: sut.generation), at: now) == .play)
    }

    @Test
    func handle_userReturned_when_not_sleeping_does_nothing() {
        var sut = PetStateMachine()
        #expect(sut.handle(.userReturned, at: now) == nil)
        #expect(sut.state == .play)
    }

    @Test
    func handle_build_events_show_build_then_celebrate_then_play() {
        var sut = PetStateMachine()
        #expect(sut.handle(.buildStarted, at: now) == .build)
        #expect(sut.handle(.buildSucceeded, at: now) == .celebrate)
        #expect(sut.handle(.oneShotFinished(generation: sut.generation), at: now) == .play)
    }

    @Test
    func handle_buildFailed_without_buildStarted_plays_fail() {
        var sut = PetStateMachine()
        #expect(sut.handle(.buildFailed, at: now) == .fail)
    }

    @Test
    func handle_buildStarted_while_sleeping_shows_build_and_returns_to_sleep_after_reaction() {
        var sut = PetStateMachine()
        sut.handle(.userIdle, at: now)
        #expect(sut.handle(.buildStarted, at: now) == .build)
        #expect(sut.handle(.buildSucceeded, at: now) == .celebrate)
        #expect(sut.handle(.oneShotFinished(generation: sut.generation), at: now) == .sleep)
    }

    @Test
    func handle_userIdle_during_celebrate_keeps_reaction_until_finished() {
        var sut = PetStateMachine()
        sut.handle(.buildSucceeded, at: now)
        #expect(sut.handle(.userIdle, at: now) == nil)
        #expect(sut.state == .celebrate)
        #expect(sut.handle(.oneShotFinished(generation: sut.generation), at: now) == .sleep)
    }

    @Test
    func handle_buildStarted_interrupts_random_act() {
        var sut = PetStateMachine()
        sut.handle(.randomAct(.faceWash), at: now)
        #expect(sut.handle(.buildStarted, at: now) == .build)
    }

    @Test
    func handle_randomAct_is_ignored_unless_playing() {
        var sut = PetStateMachine()
        sut.handle(.agentStarted, at: now)
        #expect(sut.handle(.randomAct(.lookAround), at: now) == nil)
        #expect(sut.state == .work)
    }

    @Test
    func handle_randomAct_ignores_non_one_shot_states() {
        var sut = PetStateMachine()
        #expect(sut.handle(.randomAct(.sleep), at: now) == nil)
    }

    @Test
    func handle_agent_events_show_work_then_wave() {
        var sut = PetStateMachine()
        #expect(sut.handle(.agentStarted, at: now) == .work)
        #expect(sut.handle(.agentFinished, at: now) == .wave)
        #expect(sut.handle(.oneShotFinished(generation: sut.generation), at: now) == .play)
    }

    @Test
    func handle_build_takes_precedence_over_agent_work() {
        var sut = PetStateMachine()
        sut.handle(.agentStarted, at: now)
        #expect(sut.handle(.buildStarted, at: now) == .build)
        #expect(sut.handle(.buildSucceeded, at: now) == .celebrate)
        #expect(sut.handle(.oneShotFinished(generation: sut.generation), at: now) == .work)
    }

    @Test
    func handle_lower_priority_reaction_does_not_interrupt_higher_one() {
        var sut = PetStateMachine()
        sut.handle(.buildFailed, at: now)
        #expect(sut.handle(.agentFinished, at: now) == nil)
        #expect(sut.state == .fail)
    }

    @Test
    func handle_same_reaction_within_duplicate_interval_is_ignored() {
        var sut = PetStateMachine()
        sut.handle(.buildSucceeded, at: now)
        #expect(sut.handle(.buildSucceeded, at: now.addingTimeInterval(1)) == nil)
        #expect(sut.handle(.buildSucceeded, at: now.addingTimeInterval(3)) == .celebrate)
    }

    @Test
    func handle_stale_oneShotFinished_is_ignored() {
        var sut = PetStateMachine()
        sut.handle(.buildSucceeded, at: now)
        let staleGeneration = sut.generation
        sut.handle(.buildFailed, at: now)
        #expect(sut.handle(.oneShotFinished(generation: staleGeneration), at: now) == nil)
        #expect(sut.state == .fail)
    }

    @Test
    func handle_longSession_plays_drowsy_only_while_playing() {
        var sut = PetStateMachine()
        #expect(sut.handle(.longSession, at: now) == .drowsy)
        sut.handle(.oneShotFinished(generation: sut.generation), at: now)
        sut.handle(.userIdle, at: now)
        #expect(sut.handle(.longSession, at: now) == nil)
    }
}
