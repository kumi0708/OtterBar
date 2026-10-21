import Testing

@testable import DataSource

struct PetStateTests {
    @Test
    func resourceNames_for_play_uses_runner_frames() {
        #expect(Runner(kind: .otter).resourceNames(for: .play) == (0 ..< 24).map { "otter-frame-\($0)" })
    }

    @Test
    func resourceNames_for_reaction_uses_state_prefixed_frames() {
        #expect(Runner(kind: .otter).resourceNames(for: .faceWash).first == "otter-face-wash-frame-0")
        #expect(Runner(kind: .otter).resourceNames(for: .faceWash).count == 16)
    }

    @Test
    func duration_is_frames_divided_by_twice_the_speed() {
        #expect(PetState.celebrate.duration == 16.0 / 12.0)
        #expect(PetState.play.duration == nil)
    }

    @Test
    func init_notificationName_maps_known_names_only() {
        #expect(PetEvent(notificationName: "com.otterbar.agent.finished") == .agentFinished)
        #expect(PetEvent(notificationName: "com.example.other") == nil)
    }

    @Test
    func isPet_is_true_only_for_otter() {
        #expect(Runner(kind: .otter).isPet)
        #expect(!Runner(kind: .cat).isPet)
    }

    @Test
    func speed_multiplies_cpu_linked_speed_up_to_maximum_and_keeps_fixed_speed() {
        #expect(PetState.play.speed(forRunnerSpeed: 2.0) == 4.0)
        #expect(PetState.play.speed(forRunnerSpeed: 20.0) == 16.0)
        #expect(PetState.celebrate.speed(forRunnerSpeed: 20.0) == 6.0)
    }
}
