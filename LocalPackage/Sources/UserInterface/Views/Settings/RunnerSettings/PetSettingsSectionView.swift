/*
 PetSettingsSectionView.swift
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
import Model
import SwiftUI

struct PetSettingsSectionView: View {
    @StateObject var store: PetSettings

    var body: some View {
        Section {
            LabeledContent {
                Text(store.currentState.localizedName)
            } label: {
                Text("petCurrentState", bundle: .module)
            }
            Toggle(isOn: Binding<Bool>(
                get: { store.reactsToIdle },
                asyncSet: { await store.send(.reactsToIdleToggleSwitched($0)) }
            )) {
                Text("petReactsToIdle", bundle: .module)
            }
            Stepper(
                value: Binding<Int>(
                    get: { store.idleMinutes },
                    asyncSet: { await store.send(.idleMinutesChanged($0)) }
                ),
                in: PetSettings.idleMinutesRange
            ) {
                Text("petIdleMinutes \(store.idleMinutes)", bundle: .module)
            }
            .disabled(!store.reactsToIdle)
            Toggle(isOn: Binding<Bool>(
                get: { store.randomActs },
                asyncSet: { await store.send(.randomActsToggleSwitched($0)) }
            )) {
                Text("petRandomActs", bundle: .module)
            }
            Toggle(isOn: Binding<Bool>(
                get: { store.reactsToEvents },
                asyncSet: { await store.send(.reactsToEventsToggleSwitched($0)) }
            )) {
                Text("petReactsToEvents", bundle: .module)
            }
            LabeledContent {
                HStack {
                    ForEach(PetSettings.trialEvents, id: \.self) { event in
                        Button {
                            Task {
                                await store.send(.trialButtonTapped(event))
                            }
                        } label: {
                            Text(event.localizedName)
                        }
                    }
                }
                .controlSize(.small)
            } label: {
                Text("petTryReactions", bundle: .module)
            }
            .disabled(!store.reactsToEvents)
        } header: {
            Text("petSection", bundle: .module)
        } footer: {
            Text("petSectionFooter", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            await store.send(.task)
        }
    }
}

extension PetSettings: ObservableObject {}
