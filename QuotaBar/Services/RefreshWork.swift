import Foundation

/// Isolation-safe refresh helpers.
///
/// `AppStore` is `@MainActor`. A `withTaskGroup` whose children inherit that
/// actor will deadlock: the parent `for await` sits on MainActor while
/// `URLSession` / OAuth work also needs MainActor. ChatGPT never leaves
/// `.loading`, later providers stay `.idle`, and the popover shows Updating…
/// for both. All network work runs in `Task.detached` (or a nonisolated
/// task group) and only Sendable snapshots hop back to MainActor.
enum RefreshWork {
    static let httpTimeout: TimeInterval = 20
    static let oauthTimeout: TimeInterval = 15
    static let chatGPTAccountTimeout: TimeInterval = 45
    static let providerTimeout: TimeInterval = 30

    /// Always leaves MainActor. Safe to call from `@MainActor` refresh paths.
    static func detached<T: Sendable>(
        _ operation: @Sendable @escaping () async -> T
    ) async -> T {
        await Task.detached(priority: .userInitiated) {
            await operation()
        }.value
    }

    static func detachedThrowing<T: Sendable>(
        _ operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await Task.detached(priority: .userInitiated) {
            try await operation()
        }.value
    }

    /// Sibling timeout so a hung `URLSession` cannot block forever.
    /// Always hops off MainActor — a MainActor-isolated group can deadlock
    /// the same way as ChatGPT refresh.
    static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        let limit = max(seconds, 0.1)
        return try await detachedThrowing {
            try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask {
                    try await operation()
                }
                group.addTask {
                    let nanoseconds = UInt64(clamping: Int64((limit * 1_000_000_000).rounded()))
                    try await Task.sleep(nanoseconds: nanoseconds)
                    throw QuotaError.network("Timed out after \(Int(limit.rounded()))s.")
                }
                do {
                    guard let result = try await group.next() else {
                        throw QuotaError.network("Timed out after \(Int(limit.rounded()))s.")
                    }
                    group.cancelAll()
                    return result
                } catch {
                    group.cancelAll()
                    throw error
                }
            }
        }
    }

    /// Fan-out that does not inherit MainActor. Each `work` item should hop
    /// off the actor itself if it still needs to call `@MainActor` store APIs.
    static func mapConcurrent<Job: Sendable, Output: Sendable>(
        _ jobs: [Job],
        work: @Sendable @escaping (Job) async -> Output
    ) async -> [Output] {
        await detached {
            await withTaskGroup(of: Output.self) { group in
                for job in jobs {
                    group.addTask {
                        await work(job)
                    }
                }
                var results: [Output] = []
                results.reserveCapacity(jobs.count)
                for await item in group {
                    results.append(item)
                }
                return results
            }
        }
    }

    static func quotaError(_ error: Error) -> QuotaError {
        if let quota = error as? QuotaError {
            return quota
        }
        if error is CancellationError {
            return .network("Timed out.")
        }
        return .network(error.localizedDescription)
    }

    static func performChatGPT(
        _ job: ChatGPTFetchJob
    ) async -> AccountFetchResult {
        await detached {
            do {
                let snapshot = try await withTimeout(seconds: chatGPTAccountTimeout) {
                    try await fetchChatGPT(job)
                }
                return AccountFetchResult(id: job.id, previous: job.previous, result: .success(snapshot))
            } catch {
                return AccountFetchResult(id: job.id, previous: job.previous, result: .failure(quotaError(error)))
            }
        }
    }

    static func performOpenCodeGo(
        _ job: OpenCodeGoFetchJob
    ) async -> AccountFetchResult {
        await detached {
            do {
                let snapshot = try await withTimeout(seconds: providerTimeout) {
                    try await fetchOpenCodeGo(job)
                }
                return AccountFetchResult(id: job.id, previous: job.previous, result: .success(snapshot))
            } catch {
                return AccountFetchResult(id: job.id, previous: job.previous, result: .failure(quotaError(error)))
            }
        }
    }

    static func performGrok(
        _ job: GrokFetchJob
    ) async -> AccountFetchResult {
        await detached {
            do {
                let snapshot = try await withTimeout(seconds: providerTimeout) {
                    try await fetchGrok(job)
                }
                return AccountFetchResult(id: job.id, previous: job.previous, result: .success(snapshot))
            } catch {
                return AccountFetchResult(id: job.id, previous: job.previous, result: .failure(quotaError(error)))
            }
        }
    }

    static func performSingle(_ job: SingleProviderFetchJob) async -> Result<UsageSnapshot, QuotaError> {
        await detached {
            do {
                let snapshot = try await withTimeout(seconds: providerTimeout) {
                    try await fetchSingle(job)
                }
                return .success(snapshot)
            } catch {
                return .failure(quotaError(error))
            }
        }
    }

    private static func fetchChatGPT(_ job: ChatGPTFetchJob) async throws -> UsageSnapshot {
        if job.preview {
            return try FixtureLoader.load(
                .chatgpt,
                now: Date(),
                variant: job.variant,
                emailOverride: job.email
            )
        }
        return try await ChatGPTClient.fetch(
            cookie: job.cookie,
            pastedJSON: job.json,
            codexHomePath: job.home,
            allowAmbientCodex: job.allowAmbient,
            expectedEmail: job.email
        )
    }

    private static func fetchOpenCodeGo(_ job: OpenCodeGoFetchJob) async throws -> UsageSnapshot {
        if job.preview {
            return try FixtureLoader.load(
                .opencodeGo,
                now: Date(),
                variant: job.variant,
                emailOverride: job.email
            )
        }
        return try await OpenCodeGoClient.fetch(apiKey: job.apiKey)
    }

    private static func fetchGrok(_ job: GrokFetchJob) async throws -> UsageSnapshot {
        if job.preview {
            return try FixtureLoader.load(
                .grok,
                now: Date(),
                variant: job.variant,
                emailOverride: job.email
            )
        }
        return try await GrokClient.fetch(
            pastedToken: job.pastedToken,
            useAmbientFile: job.useAmbientFile,
            allowEnvironment: job.allowEnvironment
        )
    }

    private static func fetchSingle(_ job: SingleProviderFetchJob) async throws -> UsageSnapshot {
        if job.preview {
            return try FixtureLoader.load(job.provider, now: Date())
        }
        switch job.provider {
        case .cursor:
            return try await CursorClient.fetch(cookie: job.cursorCookie)
        case .glm:
            return try await GLMClient.fetch(apiKey: job.glmAPIKey, region: job.glmRegion)
        case .chatgpt, .opencodeGo, .grok:
            throw QuotaError.schema("Use the multi-account refresh path.")
        }
    }
}

struct ChatGPTFetchJob: Sendable {
    var id: UUID
    var previous: ProviderLoadState
    var cookie: String?
    var json: String?
    var home: String?
    var allowAmbient: Bool
    var email: String?
    var preview: Bool
    var variant: Int
}

struct OpenCodeGoFetchJob: Sendable {
    var id: UUID
    var previous: ProviderLoadState
    var apiKey: String?
    var email: String?
    var preview: Bool
    var variant: Int
}

struct GrokFetchJob: Sendable {
    var id: UUID
    var previous: ProviderLoadState
    var pastedToken: String?
    var useAmbientFile: Bool
    var allowEnvironment: Bool
    var email: String?
    var preview: Bool
    var variant: Int
}

struct SingleProviderFetchJob: Sendable {
    var provider: ProviderKind
    var preview: Bool
    var cursorCookie: String?
    var glmAPIKey: String?
    var glmRegion: GLMRegion
}

struct AccountFetchResult: Sendable {
    var id: UUID
    var previous: ProviderLoadState
    var result: Result<UsageSnapshot, QuotaError>
}
