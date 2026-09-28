#!/usr/bin/env python3
"""Capture every GitHub review surface needed by baby-sit-pr as one JSON document."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import subprocess
import sys
from typing import Any


def run(*args: str) -> str:
    result = subprocess.run(
        list(args),
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode:
        command = " ".join(args)
        raise RuntimeError(f"{command} failed: {result.stderr.strip()}")
    return result.stdout


def run_json(*args: str) -> Any:
    output = run(*args).strip()
    return json.loads(output) if output else None


def paginated(endpoint: str) -> list[dict[str, Any]]:
    pages = run_json("gh", "api", "--paginate", "--slurp", endpoint) or []
    return [item for page in pages for item in page]


def select(item: dict[str, Any], *keys: str) -> dict[str, Any]:
    return {key: item.get(key) for key in keys}


def issue_comments(endpoint: str) -> list[dict[str, Any]]:
    comments = paginated(endpoint)
    return [
        {
            **select(comment, "id", "node_id", "html_url", "body", "created_at", "updated_at", "author_association"),
            "author": (comment.get("user") or {}).get("login"),
        }
        for comment in comments
    ]


def reviews(endpoint: str) -> list[dict[str, Any]]:
    items = paginated(endpoint)
    return [
        {
            **select(review, "id", "node_id", "html_url", "body", "state", "submitted_at", "commit_id", "author_association"),
            "author": (review.get("user") or {}).get("login"),
        }
        for review in items
    ]


def review_comments(endpoint: str) -> list[dict[str, Any]]:
    comments = paginated(endpoint)
    keys = (
        "id",
        "node_id",
        "pull_request_review_id",
        "html_url",
        "body",
        "created_at",
        "updated_at",
        "path",
        "line",
        "original_line",
        "in_reply_to_id",
        "commit_id",
        "author_association",
    )
    return [
        {**select(comment, *keys), "author": (comment.get("user") or {}).get("login")}
        for comment in comments
    ]


def review_threads(owner: str, name: str, number: int) -> list[dict[str, Any]]:
    query = """
query($owner: String!, $name: String!, $number: Int!, $cursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $cursor) {
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          originalLine
          comments(first: 100) {
            nodes {
              id
              databaseId
              url
              body
              createdAt
              updatedAt
              author { login }
            }
          }
        }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}
"""
    cursor: str | None = None
    threads: list[dict[str, Any]] = []
    while True:
        args = [
            "gh",
            "api",
            "graphql",
            "-f",
            f"query={query}",
            "-F",
            f"owner={owner}",
            "-F",
            f"name={name}",
            "-F",
            f"number={number}",
        ]
        if cursor:
            args.extend(["-F", f"cursor={cursor}"])
        data = run_json(*args)
        connection = data["data"]["repository"]["pullRequest"]["reviewThreads"]
        threads.extend(connection["nodes"])
        page = connection["pageInfo"]
        if not page["hasNextPage"]:
            return threads
        cursor = page["endCursor"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("pr", nargs="?", help="PR number or URL; defaults to current branch")
    args = parser.parse_args()

    repo = run_json("gh", "repo", "view", "--json", "nameWithOwner")["nameWithOwner"]
    owner, name = repo.split("/", 1)

    target = [args.pr] if args.pr else []
    identity = run_json(
        "gh",
        "pr",
        "view",
        *target,
        "--repo",
        repo,
        "--json",
        "number",
    )
    number = int(identity["number"])

    fields = ",".join(
        [
            "number",
            "url",
            "title",
            "body",
            "state",
            "isDraft",
            "author",
            "baseRefName",
            "headRefName",
            "headRefOid",
            "mergeable",
            "mergeStateStatus",
            "reviewDecision",
            "reviewRequests",
            "latestReviews",
            "statusCheckRollup",
            "labels",
        ]
    )
    pull_request = run_json(
        "gh",
        "pr",
        "view",
        str(number),
        "--repo",
        repo,
        "--json",
        fields,
    )

    root = f"/repos/{repo}"
    snapshot = {
        "generatedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "repository": repo,
        "pullRequest": pull_request,
        "issueComments": issue_comments(f"{root}/issues/{number}/comments"),
        "reviews": reviews(f"{root}/pulls/{number}/reviews"),
        "reviewComments": review_comments(f"{root}/pulls/{number}/comments"),
        "reviewThreads": review_threads(owner, name, number),
    }
    json.dump(snapshot, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        print(f"snapshot failed: {error}", file=sys.stderr)
        raise SystemExit(1)
