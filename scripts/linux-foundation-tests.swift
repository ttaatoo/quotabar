import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Runs the non-AppKit contracts against the real QuotaBar types.
/// XCTest is not linked here; macOS still runs QuotaBarTests.
///
/// Compile with `scripts/linux-foundation-check.sh`. That list does not include
/// CursorAuth, CursorClient, FixtureLoader, or RefreshWork, so Linux does not
/// need the SQLite3 module. `QuotaError.captured` is the cancellation mapper.

func check(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fputs("FAIL: \(message) (got \(actual))\n", stderr)
        exit(1)
    }
}

@main
enum LinuxFoundationTests {
    static func main() {
        do {
            try run()
            print("linux foundation tests passed")
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }
}

func run() throws {
let cloudflare = Data("<!DOCTYPE html><html><body>Attention Required! Cloudflare</body></html>".utf8)
checkEqual(
    HTTPClassify.classify(status: 403, data: cloudflare, contentType: "text/html"),
    .checkpoint,
    "html 403 checkpoint"
)
let sku = Data(#"{"error":"forbidden","message":"user unauthorized for this SKU"}"#.utf8)
checkEqual(
    HTTPClassify.classify(status: 403, data: sku, contentType: "application/json"),
    .failure,
    "sku 403 is http"
)
checkEqual(
    HTTPClassify.classify(status: 403, data: Data(#"{"code":"unauthenticated"}"#.utf8), contentType: "application/json"),
    .unauthorized,
    "exact unauthenticated"
)
checkEqual(
    HTTPClassify.classify(status: 200, data: Data(#"{"error":"not_authenticated"}"#.utf8), contentType: "application/json"),
    .unauthorized,
    "cursor 200 not_authenticated"
)
checkEqual(
    HTTPClassify.classify(status: 401, data: Data("{}".utf8), contentType: "application/json"),
    .unauthorized,
    "401"
)

let ready = ProviderLoadState.ready(
    UsageSnapshot(
        provider: .chatgpt,
        planName: "Plus",
        fetchedAt: Date(),
        session: nil,
        weekly: UsageWindow(title: "Weekly", remainingPercent: 40, usedPercent: 60),
        source: .live,
        extraFooter: nil
    )
)
let authNext = ProviderLoadState.afterFailure(
    previous: ready,
    error: QuotaError.unauthorized("session expired"),
    hasCredentials: true,
    signInHint: "sign in"
)
if case .failure = authNext {} else {
    fputs("FAIL: auth with credentials should be failure\n", stderr)
    exit(1)
}
let staleNext = ProviderLoadState.afterFailure(
    previous: ready,
    error: QuotaError.network("Timed out after 30s."),
    hasCredentials: true,
    signInHint: "sign in"
)
if case .stale = staleNext {} else {
    fputs("FAIL: network should be stale\n", stderr)
    exit(1)
}
let cancelled = ProviderLoadState.afterFailure(
    previous: ready,
    error: QuotaError.captured(URLError(.cancelled)),
    hasCredentials: true,
    signInHint: "sign in"
)
checkEqual(cancelled, ready, "url cancellation keeps previous")
check(QuotaError.cancelled.isCancellation, "cancelled case")
check(!QuotaError.network("cancelled").isCancellation, "lowercase cancelled string is not cancellation")

check(!ChatGPTAccountIdentity.identitiesMatch(nil, nil), "nil emails do not match")
check(ChatGPTAccountIdentity.emailsCompatible(nil, "a@example.com"), "missing email is compatible")
checkEqual(Percent.clamp(140), 100, "clamp high")
checkEqual(Percent.remaining(used: -5), 100, "remaining clamps")
check(JSONNumber.double(from: "nan") == nil, "nan string")

let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("qb-linux-\(UUID().uuidString)", isDirectory: true)
let homeA = root.appendingPathComponent("a", isDirectory: true)
let homeB = root.appendingPathComponent("b", isDirectory: true)
try FileManager.default.createDirectory(at: homeA, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: homeB, withIntermediateDirectories: true)
let auth: [String: Any] = ["tokens": ["access_token": "shared-access-token"]]
let authData = try JSONSerialization.data(withJSONObject: auth)
try authData.write(to: homeA.appendingPathComponent("auth.json"))
try authData.write(to: homeB.appendingPathComponent("auth.json"))
let idA = UUID()
var accounts = [ChatGPTAccount(id: idA, label: "A", codexHomePath: homeA.path)]
let matched = ChatGPTAccountIdentity.matchExisting(
    accounts: accounts,
    homePath: homeB.path,
    accessToken: "shared-access-token"
)
checkEqual(matched?.id, idA, "disk token matches the other home")
_ = ChatGPTAccountIdentity.upsertFromHome(
    accounts: &accounts,
    homePath: homeB.path,
    email: "same@example.com",
    ambient: false,
    accessToken: "shared-access-token",
    nextLabel: "ChatGPT 2"
)
check(FileManager.default.fileExists(atPath: homeA.appendingPathComponent("auth.json").path), "old home kept")
checkEqual(accounts.count, 1, "token merge does not add a row")

let period: [String: Any] = ["currentPeriod": ["end": "2026-12-01T00:00:00Z"]]
let percent = try GrokClient.usedPercent(from: period, resetAt: Date())
check(percent == nil, "grok empty period")

let mixed = ChatGPTClient.exclusiveFallback(
    cookieIdentity: ChatGPTClient.Identity(
        accessToken: "cookie-token",
        email: "cookie@example.com",
        planName: nil,
        accountId: nil,
        planExpiresAt: nil
    ),
    cookie: "session=abc",
    codexTokens: CodexCLIAuth.Tokens(accessToken: "codex-token", email: "codex@example.com")
)
checkEqual(mixed.token, "cookie-token", "no cookie/codex mix")
checkEqual(mixed.email, "cookie@example.com", "cookie email wins")

let observations: [RefreshCoordinator.PollObservation] = [.ignored, .success]
checkEqual(RefreshCoordinator.nextPollFailureCount(current: 4, observations: observations), 0, "success resets")
checkEqual(
    RefreshCoordinator.nextPollFailureCount(current: 0, observations: [.ignored, .ignored]),
    0,
    "signed-out does not back off"
)
checkEqual(
    RefreshCoordinator.nextPollFailureCount(current: 1, observations: [.transportFailure]),
    2,
    "transport failure backs off"
)
check(
    !RefreshCoordinator.showsSyntheticSignedOutCard(savedAccountCount: 2, visibleAccountCount: 0),
    "all disabled hides synthetic card"
)

checkEqual(ConfigStore.classify(data: nil), .missing, "missing config")
checkEqual(ConfigStore.classify(data: Data("{".utf8)), .corrupt, "corrupt config")
checkEqual(ConfigStore.classify(data: Data("{}".utf8)), .decoded, "empty object decodes")
check(!ConfigStore.shouldReconcileKeychain(.corrupt), "corrupt does not reconcile")
check(!ConfigStore.shouldReconcileKeychain(.missing), "missing does not reconcile")
check(ConfigStore.shouldReconcileKeychain(.decoded), "decoded reconciles")
check(KeychainStore.isUUIDScoped("chatgpt.cookie.AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"), "uuid key")
check(!KeychainStore.isUUIDScoped("chatgpt.cookie.not-a-uuid"), "non-uuid key")

let unmanaged = root.appendingPathComponent("unmanaged", isDirectory: true)
try FileManager.default.createDirectory(at: unmanaged, withIntermediateDirectories: true)
let original = Data(#"{"tokens":{"access_token":"old"}}"#.utf8)
let unmanagedAuth = unmanaged.appendingPathComponent("auth.json")
try original.write(to: unmanagedAuth)
try CodexCLIAuth.persistRefreshedTokens(home: unmanaged, tokens: CodexCLIAuth.Tokens(accessToken: "new"))
checkEqual(try Data(contentsOf: unmanagedAuth), original, "unmanaged auth.json unchanged")

let corruptURL = root.appendingPathComponent("config.json")
let corruptBytes = Data("{\"chatgptAccounts\":".utf8)
try corruptBytes.write(to: corruptURL)
let previousOverride = ConfigStore.configURLOverride
ConfigStore.configURLOverride = corruptURL
let loaded = ConfigStore.load()
checkEqual(loaded.kind, .corrupt, "truncated file is corrupt")
let wrote = try ConfigStore.saveIfAllowed(AppSettings.default, kind: loaded.kind)
check(!wrote, "corrupt persist does not write")
checkEqual(try Data(contentsOf: corruptURL), corruptBytes, "corrupt bytes survive persist")
let again = ConfigStore.load()
checkEqual(again.kind, .corrupt, "second load still corrupt")
check(!ConfigStore.shouldReconcileKeychain(again.kind), "second load does not reconcile")
ConfigStore.configURLOverride = previousOverride
let kept = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
let storedNames = [
    "chatgpt.cookie.\(kept.uuidString)",
    "cursor.cookie",
    "grok.oauth-token",
    "chatgpt.usage-json"
]
check(
    KeychainStore.orphanedAccountNames(
        stored: storedNames,
        chatgptIDs: [kept],
        grokIDs: [],
        opencodeIDs: []
    ).isEmpty,
    "owned and legacy keys are not orphans"
)

try? FileManager.default.removeItem(at: root)
}
