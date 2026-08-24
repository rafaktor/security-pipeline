#!/usr/bin/env bash
# Roll out the security pipeline to repos: adds the caller workflow +
# dependabot.yml via a PR, and enables Dependabot security updates.
#
# Usage: ./rollout.sh repo1 [repo2 ...]        (repo names under rafaktor)
set -euo pipefail

OWNER="rafaktor"
BRANCH="chore/add-security-pipeline"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

for REPO in "$@"; do
  echo "=== $OWNER/$REPO ==="
  DIR="$WORKDIR/$REPO"

  if ! git clone --depth 1 "git@github.com:$OWNER/$REPO.git" "$DIR" 2>/dev/null; then
    echo "!! clone failed, skipping"; continue
  fi
  cd "$DIR"

  DEFAULT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

  if [ -f .github/workflows/security.yml ]; then
    echo "-- already has security.yml, skipping"; cd - >/dev/null; continue
  fi

  mkdir -p .github/workflows
  cp "$SCRIPT_DIR/templates/security.yml" .github/workflows/security.yml

  # Build dependabot.yml from detected ecosystems
  {
    echo "version: 2"
    echo "updates:"
    echo "  - package-ecosystem: github-actions"
    echo "    directory: /"
    echo "    schedule: { interval: weekly }"
    [ -f package.json ] && printf "  - package-ecosystem: npm\n    directory: /\n    schedule: { interval: weekly }\n    open-pull-requests-limit: 5\n"
    { [ -f requirements.txt ] || [ -f pyproject.toml ] || [ -f Pipfile ]; } && printf "  - package-ecosystem: pip\n    directory: /\n    schedule: { interval: weekly }\n    open-pull-requests-limit: 5\n"
    [ -f Cargo.toml ] && printf "  - package-ecosystem: cargo\n    directory: /\n    schedule: { interval: weekly }\n"
    [ -f go.mod ] && printf "  - package-ecosystem: gomod\n    directory: /\n    schedule: { interval: weekly }\n"
    [ -f pom.xml ] && printf "  - package-ecosystem: maven\n    directory: /\n    schedule: { interval: weekly }\n"
    { [ -f build.gradle ] || [ -f build.gradle.kts ]; } && printf "  - package-ecosystem: gradle\n    directory: /\n    schedule: { interval: weekly }\n"
    [ -f composer.json ] && printf "  - package-ecosystem: composer\n    directory: /\n    schedule: { interval: weekly }\n"
    [ -f Package.swift ] && printf "  - package-ecosystem: swift\n    directory: /\n    schedule: { interval: weekly }\n"
    [ -f Gemfile ] && printf "  - package-ecosystem: bundler\n    directory: /\n    schedule: { interval: weekly }\n"
  } > .github/dependabot.yml

  git checkout -b "$BRANCH"
  git add .github
  git commit -q -m "Add security pipeline: OWASP scanning on every push

Calls the central reusable workflow in $OWNER/security-pipeline:
Semgrep (OWASP Top 10), Gitleaks, Trivy, CodeQL (public repos),
and optional Claude autofix PRs. Also configures Dependabot."
  git push -q -u origin "$BRANCH"

  gh pr create --repo "$OWNER/$REPO" \
    --base "$DEFAULT_BRANCH" \
    --title "Add security pipeline (OWASP scanning on every push)" \
    --body "Adds the caller workflow for the central [security-pipeline](https://github.com/$OWNER/security-pipeline): Semgrep (OWASP Top 10), Gitleaks secret scanning, Trivy dependency/IaC scanning, CodeQL on public repos, and optional Claude autofix PRs (enable by adding an \`ANTHROPIC_API_KEY\` secret). Also configures Dependabot for detected ecosystems." \
    || echo "!! PR creation failed for $REPO"

  # Enable Dependabot alerts + automated security fix PRs
  gh api -X PUT "repos/$OWNER/$REPO/vulnerability-alerts" >/dev/null 2>&1 && echo "-- vulnerability alerts enabled"
  gh api -X PUT "repos/$OWNER/$REPO/automated-security-fixes" >/dev/null 2>&1 && echo "-- automated security fixes enabled"

  cd - >/dev/null
done
echo "Done."
