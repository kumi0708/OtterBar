/*
 DarwinNotificationClient.swift
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

import Foundation
import notify

public struct DarwinNotificationClient: DependencyClient {
    public var stream: @Sendable ([String]) -> AsyncStream<String>
    public var post: @Sendable (String) -> Void

    public static let liveValue = Self(
        stream: { names in
            AsyncStream { continuation in
                let tokens = names.map { name in
                    var token = Int32.zero
                    notify_register_dispatch(name, &token, .main) { _ in continuation.yield(name) }
                    return token
                }
                continuation.onTermination = { _ in tokens.forEach { notify_cancel($0) } }
            }
        },
        post: { notify_post($0) }
    )

    public static let testValue = Self(
        stream: { _ in AsyncStream { $0.finish() } },
        post: { _ in }
    )
}
