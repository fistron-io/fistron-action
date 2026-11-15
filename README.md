# Fistron for GitHub Actions

When your CI fails, Fistron finds every cause of each failed job, writes the
fix, verifies it in the same run and puts it on your pull request: a fix
within the lines you changed as a **suggested change** you apply with one
click, anything larger as a **pull request of its own**. Nothing is merged
by Fistron, and there is no secret to set.

```yaml
# .github/workflows/fistron.yml
name: Fistron
on:
  workflow_run:
    workflows: [ci]          # your CI workflow's name
    types: [completed]
permissions:
  contents: read
jobs:
  fistron:
    if: >-
      github.event.workflow_run.conclusion == 'failure' ||
      startsWith(github.event.workflow_run.head_branch, 'fistron/verify/')
    runs-on: ubuntu-24.04
    permissions:
      actions: write
      contents: write
      pull-requests: write
      id-token: write
    steps:
      - uses: fistron-io/fistron-action@<commit>  # v1
        with:
          verify: pip install -q -e '.[test]' && python -m pytest -q {tests}
```

## What it does

1. **The licence of this run, no secret:** the job's identity token
   (`id-token: write`, audience `fistron`) goes to `account.fistron.io`,
   which answers with a licence valid an hour, in this run only, when the
   repository is your own and you hold an Individual licence; with
   `control-plane-url`, to your organisation's control plane (Team and
   above).
2. **Every cause** of each failed job (`fistron ci`, then `fistron ci-fix`).
3. **The fix:** a test that fails by its own fault is repaired; a cause in
   the code is fixed in the files it cites, never a test. Each is verified by
   `verify` in a temporary copy of your checkout (a repaired test: 3 runs),
   or, for any language, by your own CI (`verify-workflow`): the fix on a
   branch `fistron/verify/...`, your CI started there, and the fix offered
   when it passes. Only a fix that passes is offered.
4. **The comment:** the causes, each fix and how it was verified, and what
   the model used today and this month; "Analysed by Fistron".

## Your credit does not burn

- The same failure again is answered from what was concluded, no model call.
- A day's cap for the repository and a month's share for CI (your licence's,
  or `daily-cap-eur`, `monthly-cap-eur`); at a cap, Rules — Deterministic,
  and the comment says so.
- The state is kept in the repository's Actions cache, nowhere else.

## Your own model

```yaml
        with:
          model-base-url: https://api.example.test/v1
          model-name: a-model
          model-api-key: ${{ secrets.FISTRON_LLM_API_KEY }}
```

The one secret there is, by your choice; the same caps count its prices.

## Pull requests from forks

The workflow runs in your repository's trusted context after the fork's CI.
The fork's code is never run there: its causes are given, no fix is
verified or offered.

## Inputs

| Input | Default | |
|---|---|---|
| `verify` | | the command that runs the failed tests in Fistron's image, `{tests}` being them |
| `verify-workflow` | | your CI's workflow file: it verifies each fix on a branch of its own (needs `workflow_dispatch:` and `actions: write`) |
| `publish` | `true` | the comment, suggestions and pull requests; `false`: the job summary only |
| `image` | this release's, by digest | Fistron's image with its closed core |
| `daily-cap-eur`, `monthly-cap-eur` | your licence's | the model's caps in this repository's CI |
| `control-plane-url` | | Team and above: your organisation's control plane |
| `model-base-url`, `model-name`, `model-api`, `model-api-key` | | your own model |

Apache-2.0. Fistron's closed core in the image is licensed separately.
