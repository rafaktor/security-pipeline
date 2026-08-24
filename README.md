# security-pipeline

Central security pipeline for all my repos. Every repo carries a ~15-line caller
workflow ([templates/security.yml](templates/security.yml)) that runs this repo's
reusable workflow on every push, PR, and weekly. Change
[.github/workflows/security-scan.yml](.github/workflows/security-scan.yml) here
once — every repo picks it up.

## What it runs

| Layer | Tool | Covers | Repos |
|---|---|---|---|
| SAST | **Semgrep** (`p/owasp-top-ten`, `p/security-audit`, `p/secrets`) | Injection, XSS, crypto failures, insecure design patterns | all |
| Secrets | **Gitleaks** | Committed credentials, full git history | all |
| SCA + IaC | **Trivy** | Vulnerable dependencies (OWASP A06), Dockerfile/IaC misconfig | all |
| Deep SAST | **CodeQL** (`security-extended`) | Semantic dataflow analysis | public only¹ |
| Autofix | **Claude Code** | Opens a fix PR for real findings | repos with `ANTHROPIC_API_KEY` secret |
| Dependency fixes | **Dependabot** | Automatic PRs bumping vulnerable deps | all |

¹ CodeQL and the Security tab require GitHub Advanced Security on private repos,
which is not available on personal plans. Private repos get results in each
workflow run's **job summary** instead.

## Results

- Per run: the **Summary** page of the workflow run (tables for Semgrep + Trivy).
- Public repos: also the repo's **Security → Code scanning** tab.
- Fixes: Dependabot PRs (deps) and `security-autofix/*` PRs from Claude (code).

## Options (set in the caller workflow)

```yaml
jobs:
  scan:
    uses: rafaktor/security-pipeline/.github/workflows/security-scan.yml@main
    secrets: inherit
    with:
      strict: true    # fail the build on findings (default false)
      autofix: false  # disable Claude fix PRs (default true)
```

## Enable Claude autofix on a repo

```
gh secret set ANTHROPIC_API_KEY -R rafaktor/<repo>
```

## Roll out to more repos

```
./rollout.sh repo1 repo2 ...
```

Opens a PR on each repo adding the caller workflow + a Dependabot config for its
detected ecosystems, and enables Dependabot alerts/security fixes.
