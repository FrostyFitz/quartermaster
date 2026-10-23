# Azure DevOps pull request provider verification

Empirical record for watching, merging, and observing Azure DevOps pull requests, alongside the GitHub, GitLab, and Gerrit paths.
It was collected on 2026-10-22 against a live organization with read-only commands only; the organization, project, repository, and pull request identities are elided because they are private, and every command is shown with placeholders.
No pull request was created, updated, completed, abandoned, voted on, or commented on while collecting it.

## Versions

```
$ az version
{
  "azure-cli": "2.90.0",
  "extensions": {
    "azure-devops": "1.0.7"
  }
}
```

## Per-user prerequisites

Quartermaster reads and merges Azure DevOps pull requests through `az` and its `azure-devops` extension, signed in with `az login`.
No forge token is configured: the registry's forge binding stays absent (`forge=none`), because no-mistakes already drives its own pull requests there, and quartermaster only follows the pull request it opened.
`bin/fm-pr-check.sh` and `bin/fm-pr-merge.sh` refuse before recording anything when `az` or `jq` is absent, naming the missing tool.

## Identity

An Azure DevOps pull request URL is `https://dev.azure.com/<org>/<project>/_git/<repo>/pullrequest/<id>`.
The stored identity is `azuredevops`, the URL, `dev.azure.com`, the path `<org>/<project>/_git/<repo>`, and the id.
The project and repository stay percent-encoded exactly as the URL spells them, for example `Firmware%20DevOps`.
The legacy `<org>.visualstudio.com` spelling is refused, because it carries the organization in the host and the stored identity has no field for that.

A pull request id is unique within an organization, not within a repository, and `az repos pr show` needs only the id and the organization:

```
$ az repos pr show --id <id> --org https://dev.azure.com/<org> -o json
```

Every reader therefore compares the record's `repository.project.name` and `repository.name` with the decoded names in the URL, without regard to case, and refuses a record that disagrees.
Without that comparison a URL naming one repository would read or merge another repository's pull request that shares the number.
`tests/fm-pr-check-security.test.sh` proves the poll and arming refuse such a record, and `tests/fm-pr-merge.test.sh` proves the merge does.

## What is read

State comes from one `az repos pr show` record.
The fields relied on are `status` (`active`, `completed`, `abandoned`), `isDraft`, `mergeStatus` (`succeeded` when mergeable, `conflicts` when not), `lastMergeSourceCommit.commitId` as the head, `autoCompleteSetBy`, `createdBy`, and `reviewers[].vote`.
`completed` is Azure DevOps's merged state, and the merge poll wakes only on that exact value.

Checks come from the pull request's policy evaluations:

```
$ az repos pr policy list --id <id> --org https://dev.azure.com/<org> -o json
```

Each evaluation carries `status`, `configuration.isBlocking`, `configuration.isEnabled`, `configuration.isDeleted`, `configuration.type.id`, `configuration.type.displayName`, and, for a build policy, a `context` with `buildDefinitionName`, `isExpired`, and `lastMergeSourceCommitId`.
Statuses observed on a live pull request were `approved`, `queued`, and `running`; `rejected`, `broken`, and `notApplicable` are the API's other documented values and are handled but were not observed.
Only an enabled, undeleted, blocking evaluation counts.
It is green when its status is `approved` or `notApplicable`, and a build policy is green only when it did not expire and evaluated the current head.
A required policy that is queued, running, rejected, or broken is therefore a failing or unreported check, exactly as an unreported required check is on GitHub.
The policies a person satisfies - Minimum number of reviewers, Required reviewers, and Comment requirements, identified by `configuration.type.id` and by `configuration.type.displayName` only when no id is present - are never checks.
While one is unmet the pull request reads as `REVIEW_REQUIRED`, the same review decision GitHub reports, and the merge refusal names it as a review requirement.

Threads come from the REST resource through `az`, because `az repos pr` has no thread command:

```
$ az devops invoke --area git --resource pullRequestThreads \
    --route-parameters project=<project> repositoryId=<repo> pullRequestId=<id> \
    --org https://dev.azure.com/<org> --api-version 7.1 -o json
```

The project and repository are passed decoded, so that `az`'s own route encoding is the only encoding applied.
Every non-system, non-deleted comment by someone other than the author is an incoming signal, because only members of the organization can comment.

## Merging

The merge is `az devops invoke --area git --resource pullRequests --http-method patch` against the pull request, with `{"status":"completed","lastMergeSourceCommit":{"commitId":"<verified head>"}}` as the body, after the live conditions in `bin/fm-pr-merge.sh`'s header hold.
`--bypass-policy` is never passed and is refused in the extra arguments on every path.
`az` accepts any unambiguous prefix of a long option, so every guard on the extra arguments also refuses any prefix of a protected flag, such as `--orga` for `--organization` or `--auto-comp` for `--auto-complete`.

Naming the verified head in the body binds the completion to it, as `gh --match-head-commit` and `glab --sha` do, so the server refuses a pull request whose source branch has moved.
The extra arguments after `--` map only the completion flags `--squash`, `--delete-source-branch`, `--merge-commit-message`, and `--transition-work-items` into the body's `completionOptions`, over the pull request's own options, and any other flag is refused. An attended `--attended-override -- --auto-complete true` request does not request an immediate completion: it runs `az repos pr update` without `--status completed`, with the extra arguments as given, so it only sets auto-complete, and Azure DevOps completes the pull request itself only after its branch policies pass on the head it completes. That request is handled as queued, with no landed outcome recorded and the merge poll left armed.
The read-back after completion still compares the merged head with the verified head and reports any difference as actionable.

## Reading it back

```
$ az repos pr show --id <id> --org https://dev.azure.com/<org> \
    --query '[status, repository.project.name, repository.name]' -o tsv
active
<project>
<repo>
```

This is the poll's read.
It needs no JSON processor, accepts exactly three lines, and wakes only when the first is `completed` and the other two match the URL.

## Known limits

- `bin/fm-review-diff.sh` and `bin/fm-teardown.sh` address GitHub pull request heads by `refs/pull/<n>/head`; an Azure DevOps task records no `pr_head`, as GitLab and Gerrit tasks do not, and takes their local-branch and content-check fallbacks.
- The comment monitor reports no reviews and no merge permission for Azure DevOps: a vote carries no commit to judge freshness by, and the permission is not read.
- Azure DevOps Boards work items, pipeline triggers, and a dedicated `-axi` wrapper are not part of this provider.
