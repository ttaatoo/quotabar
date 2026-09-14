#!/usr/bin/env python3
"""Focused Cursor client contracts (WAF vs auth, api2 planUsage, refresh gate)."""

from __future__ import annotations

import json
import sys


def looks_like_json(text: str) -> bool:
    trimmed = text.lstrip()
    return trimmed.startswith("{") or trimmed.startswith("[")


def looks_like_html(text: str) -> bool:
    lower = text.lstrip().lower()
    return lower.startswith("<!doctype html") or lower.startswith("<html")


def is_vercel_checkpoint(body: str) -> bool:
    lower = body.lower()
    return "vercel security checkpoint" in lower or "security checkpoint" in lower


def is_checkpoint(status: int, body: str, content_type: str | None) -> bool:
    if status != 403:
        return False
    if is_vercel_checkpoint(body):
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
    haystack = " ".join(
        str(obj.get(key) or "") for key in ("error", "code", "message")
    ).lower()
    markers = (
        "not_authenticated",
        "not authenticated",
        "unauthenticated",
        "unauthorized",
        "invalid token",
        "token expired",
    )
    return any(marker in haystack for marker in markers)


def is_unauthenticated(status: int, body: str, content_type: str | None) -> bool:
    if is_checkpoint(status, body, content_type):
        return False
    if status == 401:
        return True
    if looks_like_json(body) or "json" in (content_type or "").lower():
        try:
            obj = json.loads(body)
        except json.JSONDecodeError:
            return False
        if isinstance(obj, dict) and is_unauthenticated_json(obj):
            return True
    return False


def classify(status: int, body: str, content_type: str | None) -> str:
    if is_checkpoint(status, body, content_type):
        return "checkpoint"
    if is_unauthenticated(status, body, content_type):
        return "unauthorized"
    if 200 <= status <= 299:
        return "ok"
    return "failure"


def is_rejected_session_message(message: str) -> bool:
    lower = message.lower()
    if "security checkpoint" in lower:
        return False
    return (
        "rejected" in lower
        or "not authenticated" in lower
        or "refresh failed" in lower
        or "no refresh token" in lower
        or "401" in message
    )


def should_attempt_refresh(kind: str, error_kind: str) -> bool:
    return kind == "ambient" and error_kind == "unauthorized"


def parse_period_usage(raw: dict) -> dict:
    if is_unauthenticated_json(raw):
        raise ValueError("unauthorized")
    plan = raw.get("planUsage") or {}
    auto = plan.get("autoPercentUsed")
    api = plan.get("apiPercentUsed")
    if auto is None and api is None:
        used = plan.get("totalPercentUsed")
        if used is None and plan.get("limit"):
            used = (plan.get("includedSpend") or 0) / plan["limit"] * 100
        auto = used
    cycle = raw.get("billingCycleEnd")
    if isinstance(cycle, str) and cycle.isdigit():
        cycle_s = int(cycle) / 1000 if int(cycle) > 1_000_000_000_000 else int(cycle)
    else:
        cycle_s = None
    spend = raw.get("spendLimitUsage") or {}
    extra = None
    if (spend.get("individualLimit") or 0) > 0 or (spend.get("pooledLimit") or 0) > 0:
        used = spend.get("individualUsed") or spend.get("pooledUsed") or spend.get("totalSpend")
        if used is not None and used >= 50:
            extra = f"On-demand ${used / 100:.2f}"
    return {
        "auto": auto,
        "api": api,
        "remaining_auto": None if auto is None else 100 - auto,
        "remaining_api": None if api is None else 100 - api,
        "cycle": cycle_s,
        "extra": extra,
    }


def main() -> int:
    html = (
        "<!DOCTYPE html><html><head><title>Vercel Security Checkpoint</title></head>"
        "<body>Vercel Security Checkpoint</body></html>"
    )
    assert classify(403, html, "text/html; charset=utf-8") == "checkpoint"
    assert not is_unauthenticated(403, html, "text/html")
    assert not is_rejected_session_message(
        "Cursor usage is temporarily blocked by a security checkpoint. Try Refresh again."
    )

    auth_json = '{"error":"not_authenticated"}'
    assert classify(401, auth_json, "application/json") == "unauthorized"
    assert classify(200, auth_json, "application/json") == "unauthorized"
    assert classify(403, '{"code":"unauthenticated"}', "application/json") == "unauthorized"

    assert should_attempt_refresh("ambient", "unauthorized")
    assert not should_attempt_refresh("pasted", "unauthorized")
    assert not should_attempt_refresh("ambient", "checkpoint")
    assert not should_attempt_refresh("ambient", "http403")

    parsed = parse_period_usage(
        {
            "billingCycleEnd": "1771077734000",
            "planUsage": {
                "autoPercentUsed": 7.2,
                "apiPercentUsed": 12.0,
                "totalPercentUsed": 15.48,
                "includedSpend": 23222,
                "limit": 40000,
            },
            "spendLimitUsage": {"individualLimit": 10000, "individualUsed": 245},
        }
    )
    assert abs(parsed["auto"] - 7.2) < 1e-6
    assert abs(parsed["remaining_auto"] - 92.8) < 1e-6
    assert abs(parsed["api"] - 12.0) < 1e-6
    assert parsed["cycle"] == 1_771_077_734
    assert parsed["extra"] == "On-demand $2.45"

    spend_only = parse_period_usage(
        {
            "billingCycleEnd": "1771077734000",
            "planUsage": {"includedSpend": 2000, "limit": 40000, "totalPercentUsed": 5.0},
        }
    )
    assert abs(spend_only["auto"] - 5.0) < 1e-6
    assert spend_only["api"] is None

    try:
        parse_period_usage({"error": "not_authenticated"})
        raise AssertionError("expected unauthorized")
    except ValueError as exc:
        assert "unauthorized" in str(exc)

    print("cursor client contract tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
