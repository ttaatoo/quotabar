#!/usr/bin/env python3
"""Illustrative notes for the audit fixes. NOT proof.

This script reimplements a simplified model of the Swift control flow.
It does not compile or execute any .swift file. A green run here does not
mean QuotaBar or QuotaBarTests build. The Swift tests under QuotaBarTests/
and scripts/linux-foundation-tests.swift are the checks that exercise the
real types.
"""

from __future__ import annotations

import json


def looks_like_json(text: str) -> bool:
    trimmed = text.lstrip()
    return trimmed.startswith("{") or trimmed.startswith("[")


def looks_like_html(text: str) -> bool:
    lower = text.lstrip().lower()
    return lower.startswith("<!doctype html") or lower.startswith("<html")


def is_checkpoint_body(body: str) -> bool:
    lower = body.lower()
    return (
        "vercel security checkpoint" in lower
        or "security checkpoint" in lower
        or "attention required" in lower
        or "cf-error" in lower
        or "cloudflare" in lower
    )


def is_checkpoint(status: int, body: str, content_type: str | None) -> bool:
    if status != 403:
        return False
    if is_checkpoint_body(body):
        return True
    type_l = (content_type or "").lower()
    if "text/html" in type_l:
        return True
    return looks_like_html(body) and not looks_like_json(body)


def is_unauthenticated_json(obj: dict) -> bool:
    if obj.get("error") == "not_authenticated":
        return True
    if obj.get("shouldLogout") is True:
        return True
    haystack = " ".join(str(obj.get(key) or "") for key in ("error", "code", "message")).lower()
    markers = (
        "not_authenticated",
        "not authenticated",
        "unauthenticated",
        "unauthorized",
        "invalid token",
        "token expired",
        "invalid_grant",
    )
    return any(marker in haystack for marker in markers)


def classify(status: int, body: str, content_type: str | None) -> str:
    if is_checkpoint(status, body, content_type):
        return "checkpoint"
    if status == 401:
        return "unauthorized"
    if looks_like_json(body) or "json" in (content_type or "").lower():
        try:
            obj = json.loads(body)
        except json.JSONDecodeError:
            obj = None
        if isinstance(obj, dict) and is_unauthenticated_json(obj):
            return "unauthorized"
    if status == 429:
        return "rateLimited"
    if 200 <= status <= 299:
        return "ok"
    return "failure"


def require_ok(status: int, body: str, content_type: str | None = None) -> str:
    kind = classify(status, body, content_type)
    return {
        "ok": "ok",
        "unauthorized": "unauthorized",
        "checkpoint": "network-checkpoint",
        "rateLimited": "http-429",
        "failure": f"http-{status}",
    }[kind]


def is_auth_failure(kind: str) -> bool:
    return kind in {"notSignedIn", "unauthorized", "http-401"}


def should_preserve(error_kind: str) -> bool:
    return error_kind == "network" or error_kind.startswith("network-")


def after_failure(previous: str, error_kind: str, has_credentials: bool) -> str:
    if error_kind == "cancelled":
        return previous
    if previous in {"ready", "stale"} and should_preserve(error_kind):
        return "stale"
    if is_auth_failure(error_kind) and not has_credentials:
        return "signedOut"
    return "failure"


def should_show_loading(state: str) -> bool:
    return state in {"idle", "loading"}


def shows_user_initiated_loading(state: str) -> bool:
    return state != "ready"


def identities_match(lhs: str | None, rhs: str | None) -> bool:
    def usable(value: str | None) -> str | None:
        if not value or "@" not in value or " " in value.strip():
            return None
        return value.strip()

    left, right = usable(lhs), usable(rhs)
    if left is None or right is None:
        return False
    return left.lower() == right.lower()


def upsert_chatgpt_by_home(accounts: list[dict], email: str, home: str, token: str) -> list[dict]:
    for account in accounts:
        if account.get("home") == home or account.get("token") == token:
            account["home"] = home
            if email and not any(
                a is not account and a.get("email", "").lower() == email.lower() for a in accounts
            ):
                account["email"] = email
            return accounts
    accounts.append({"email": email, "home": home, "token": token})
    return accounts


def visible_accounts(accounts: list[dict]) -> list[dict]:
    return [account for account in accounts if account.get("enabled", True)]


def percent_clamp(value: float) -> float:
    if value != value or value in (float("inf"), float("-inf")):
        return 0.0
    return min(100.0, max(0.0, value))


class RefreshCoordinator:
    def __init__(self) -> None:
        self.generations: dict[str, int] = {}
        self.in_flight: set[str] = set()

    def begin(self, key: str) -> int:
        nxt = self.generations.get(key, 0) + 1
        self.generations[key] = nxt
        self.in_flight.add(key)
        return nxt

    def finish(self, key: str, generation: int) -> None:
        if self.generations.get(key) == generation:
            self.in_flight.discard(key)

    def is_current(self, key: str, generation: int) -> bool:
        return self.generations.get(key) == generation

    @property
    def refreshing(self) -> bool:
        return bool(self.in_flight)


def grok_used_percent(credit_usage: float | None, reset_at: bool) -> float | None:
    if credit_usage is not None:
        return credit_usage
    if reset_at:
        return None
    return None


def opencode_403(body: str) -> str:
    try:
        obj = json.loads(body)
    except json.JSONDecodeError:
        return "http-403"
    name = str(obj.get("name") or obj.get("error") or obj.get("code") or obj.get("type") or "")
    if "entitlement" in name.lower():
        return "no-subscription"
    return "http-403"


def recovery(state: str, message: str, provider: str) -> str:
    expired = "token expired" in message.lower() or "re-login" in message.lower()
    session = "session cookie" in message.lower() or "codex login expired" in message.lower()
    if state in {"failure", "signedOut", "stale"} and provider == "grok" and expired:
        return "relogin"
    if state in {"failure", "signedOut", "stale"} and provider == "chatgpt" and (expired or session):
        return "relogin"
    return "retryRefresh"


def exclusive_fallback(cookie_identity: dict | None, cookie: str | None, codex_tokens: dict | None) -> dict:
    if cookie_identity:
        return {
            "token": cookie_identity["token"],
            "cookie": cookie,
            "email": cookie_identity["email"],
        }
    if codex_tokens:
        return {
            "token": codex_tokens["token"],
            "cookie": None,
            "email": codex_tokens["email"],
        }
    return {"token": None, "cookie": None, "email": None}


def needs_open_refresh(state: str, age_seconds: float, force: bool) -> bool:
    if force:
        return True
    if state == "ready":
        return age_seconds > 30
    return True


def main() -> int:
    cloudflare = "<!DOCTYPE html><html><body>Attention Required! Cloudflare</body></html>"
    assert require_ok(403, cloudflare, "text/html") == "network-checkpoint"
    assert require_ok(403, "Vercel Security Checkpoint") == "network-checkpoint"
    assert require_ok(403, '{"error":"forbidden"}', "application/json") == "http-403"
    assert not is_auth_failure("http-403")
    assert require_ok(401, "{}", "application/json") == "unauthorized"
    assert require_ok(429, "rate limited") == "http-429"
    assert require_ok(503, "down") == "http-503"
    assert classify(403, '{"code":"unauthenticated"}', "application/json") == "unauthorized"
    assert classify(403, '{"error":"forbidden","message":"token expired"}', "application/json") == "unauthorized"

    assert after_failure("ready", "unauthorized", True) == "failure"
    assert after_failure("ready", "notSignedIn", True) == "failure"
    assert after_failure("ready", "network", True) == "stale"
    assert after_failure("idle", "unauthorized", False) == "signedOut"
    assert after_failure("ready", "cancelled", True) == "ready"

    assert shows_user_initiated_loading("failure") is True
    assert shows_user_initiated_loading("ready") is False
    assert should_show_loading("failure") is False

    assert recovery("failure", "Grok token expired. Re-login this account.", "grok") == "relogin"
    assert recovery("stale", "Grok token expired. Re-login this account.", "grok") == "relogin"
    assert recovery("ready", "Grok token expired. Re-login this account.", "grok") == "retryRefresh"
    assert recovery("failure", "chatgpt.com rejected the session cookie.", "chatgpt") == "relogin"

    accounts = [{"email": "same@example.com", "home": "/home/a", "token": "tok-a"}]
    upsert_chatgpt_by_home(accounts, "same@example.com", "/home/b", "tok-b")
    assert len(accounts) == 2
    assert identities_match(None, "a@example.com") is False
    assert identities_match(None, None) is False
    assert identities_match("a@example.com", "b@example.com") is False

    hidden = [{"id": "1", "enabled": False}, {"id": "2", "enabled": False}]
    assert visible_accounts(hidden) == []

    assert percent_clamp(140.0) == 100.0
    assert percent_clamp(-5.0) == 0.0

    coord = RefreshCoordinator()
    g1 = coord.begin("chatgpt")
    g2 = coord.begin("chatgpt")
    assert coord.refreshing is True
    assert coord.is_current("chatgpt", g1) is False
    coord.finish("chatgpt", g1)
    assert coord.refreshing is True
    coord.finish("chatgpt", g2)
    assert coord.refreshing is False

    assert grok_used_percent(None, reset_at=True) is None
    assert opencode_403('{"name":"EntitlementError"}') == "no-subscription"
    assert opencode_403("<html>nope</html>") == "http-403"

    mixed = exclusive_fallback(
        {"token": "cookie-token", "email": "cookie@example.com"},
        "session=abc",
        {"token": "codex-token", "email": "codex@example.com"},
    )
    assert mixed["token"] == "cookie-token"
    assert mixed["email"] == "cookie@example.com"
    assert mixed["cookie"] == "session=abc"
    codex_only = exclusive_fallback(None, "session=abc", {"token": "codex-token", "email": "codex@example.com"})
    assert codex_only["token"] == "codex-token"
    assert codex_only["cookie"] is None

    assert needs_open_refresh("ready", 10, force=False) is False
    assert needs_open_refresh("ready", 45, force=False) is True
    assert needs_open_refresh("failure", 1, force=False) is True
    assert needs_open_refresh("ready", 1, force=True) is True

    print("illustrative audit model passed (not a Swift build)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
