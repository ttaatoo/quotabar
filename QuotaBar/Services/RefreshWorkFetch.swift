import Foundation

extension RefreshWork {
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
            allowEnvironment: job.allowEnvironment,
            grokHomePath: job.grokHomePath
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
