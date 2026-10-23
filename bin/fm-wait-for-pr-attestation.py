#!/usr/bin/env python3
"""Poll a PR's live body for a no-mistakes attestation naming the current head.

`require-no-mistakes` (the shared gate action) already reads the PR's live
body and head SHA from the GitHub API, so a `synchronize` run started right
after a no-mistakes push can still observe the PREVIOUS head's attestation:
the pipeline's PR-body rewrite for the new head has not landed yet. This
script runs before that action, on `synchronize`/`reopened` only, and gives
the body a short bounded window to catch up before the gate judges it.

It never fails the job itself. If the attestation catches up, it returns
early; if the window expires first, it returns anyway and lets the gate
action's own live lookup render (and message) the real verdict - including a
genuinely stale or missing attestation, which must still fail with the gate's
existing error, not this script's.

Required env: GITHUB_TOKEN, REPO (owner/name), PR_NUMBER, HEAD_SHA.
Optional env: GITHUB_API_URL (default https://api.github.com), used by tests
to point at a local stub server instead of the real API.
NM_WAIT_MAX_SECONDS (default 180) and NM_WAIT_POLL_SECONDS (default 10)
bound and pace the wait; tests shrink both to keep runs fast. A value that
does not parse falls back to its default.

A transient read failure (a network error, a truncated or non-JSON body, a 5xx,
a 429, or a rate-limit 403) is retried until the deadline, because ending the
wait early would leave the gate to read the previous head's attestation. Only
an error waiting cannot fix (401, 404, or any other 4xx) ends the wait early.
"""
from __future__ import annotations

import http.client
import json
import os
import sys
import time
import urllib.error
import urllib.request

ATTESTATION_PREFIX = "<!-- no-mistakes-pipeline-attestation:v1 "
ATTESTATION_CLOSING = " -->"


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def attested_head(body: str) -> str | None:
    start = body.find(ATTESTATION_PREFIX)
    if start == -1:
        return None
    start += len(ATTESTATION_PREFIX)
    end = body.find(ATTESTATION_CLOSING, start)
    if end == -1:
        return None
    try:
        parsed = json.loads(body[start:end])
    except json.JSONDecodeError:
        return None
    head = parsed.get("head_sha") if isinstance(parsed, dict) else None
    return head if isinstance(head, str) else None


def live_body(api_url: str, repo: str, pr_number: str, token: str) -> str:
    url = f"{api_url}/repos/{repo}/pulls/{pr_number}"
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
        },
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        payload = json.load(resp)
    return payload.get("body") or ""


def number(name: str, default: float) -> float:
    try:
        return float(env(name, str(default)))
    except ValueError:
        return default


def main() -> int:
    token = env("GITHUB_TOKEN")
    repo = env("REPO")
    pr_number = env("PR_NUMBER")
    head_sha = env("HEAD_SHA")
    if not (token and repo and pr_number and head_sha):
        print("::error::GITHUB_TOKEN, REPO, PR_NUMBER, and HEAD_SHA are all required", file=sys.stderr)
        return 1

    api_url = env("GITHUB_API_URL", "https://api.github.com").rstrip("/")
    max_seconds = number("NM_WAIT_MAX_SECONDS", 180)
    poll_seconds = number("NM_WAIT_POLL_SECONDS", 10)
    deadline = time.monotonic() + max_seconds

    while True:
        try:
            body = live_body(api_url, repo, pr_number, token)
        except urllib.error.HTTPError as exc:
            if 400 <= exc.code < 500 and exc.code not in (403, 408, 429):
                print(f"::warning::could not read the live PR body while waiting for the attestation: {exc}")
                return 0
            body = None
        except (OSError, http.client.HTTPException, ValueError) as exc:
            print(f"::warning::could not read the live PR body while waiting for the attestation, retrying: {exc}")
            body = None
        if body is not None and attested_head(body) == head_sha:
            print(f"pipeline attestation already names the current head {head_sha}")
            return 0
        if time.monotonic() >= deadline:
            print(f"attestation did not catch up to {head_sha} within the wait window; judging as-is")
            return 0
        time.sleep(poll_seconds)


if __name__ == "__main__":
    sys.exit(main())
