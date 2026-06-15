---
description: Watch PR checks and analyze results
disable-model-invocation: true
context: fork
agent: general-purpose
model: haiku
---

Watch the current PR's CI checks until they complete, then analyze failures and review comments.

## Steps

1. **Detect the current PR.** Run `gh pr view --json number,url,headRefName,title` to get the PR number, URL, and branch. If there's no PR for the current branch, tell the user and stop.

2. **Poll checks until complete.** Run `gh pr checks --watch --fail-fast` to block until all checks finish (or one fails). This will print the final status of each check.

3. **Gather check results.** Run `gh pr checks` to get the final pass/fail summary of all checks.

4. **For each failed check:**
   - Extract the workflow run ID from the failed check's URL (the numeric ID in the URL path).
   - Fetch failed job logs using `gh api repos/{owner}/{repo}/actions/runs/{run_id}/jobs` to find the failed job IDs, then `gh api repos/{owner}/{repo}/actions/jobs/{job_id}/logs` to get logs.
   - Extract the most relevant failure lines from the logs (error messages, assertion failures, stack traces). Keep it concise — show only what's needed to understand the failure.

5. **Gather review feedback.** Bot reviewers (e.g. Claude) often edit their comment in-place with findings from the latest CI run, so always re-fetch comments after checks complete — don't rely on earlier snapshots. Use:
   - `gh api repos/{owner}/{repo}/pulls/{number}/reviews` for top-level reviews
   - `gh api repos/{owner}/{repo}/pulls/{number}/comments` for inline review comments
   - `gh api repos/{owner}/{repo}/issues/{number}/comments` for issue-level comments (this is where bot reviews like Claude's appear)
   - Skip if there are no reviews or comments.

6. **Report results.** Provide a concise summary:
   - List which checks passed and which failed
   - For failures: show the relevant error/log snippet and a brief diagnosis
   - For review comments: group by file, quote the key points
   - Suggest concrete next steps (what to fix, what to address)
