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

  # Build dependabot.yml from detected ecosystems.
  # Minor+patch bumps are grouped into one weekly PR per ecosystem; majors stay
  # individual so breaking changes get their own review.
  eco() { # eco <ecosystem> [limit]
    printf "  - package-ecosystem: %s\n    directory: /\n    schedule: { interval: weekly }\n" "$1"
    [ -n "${2:-}" ] && printf "    open-pull-requests-limit: %s\n" "$2"
    printf "    groups:\n      %s-minor-patch:\n        applies-to: version-updates\n        update-types: [\"minor\", \"patch\"]\n" "$1"
  }
  {
    echo "version: 2"
    echo "updates:"
    eco github-actions
    [ -f package.json ] && eco npm 5
    { [ -f requirements.txt ] || [ -f pyproject.toml ] || [ -f Pipfile ]; } && eco pip 5
    [ -f Cargo.toml ] && eco cargo
    [ -f go.mod ] && eco gomod
    [ -f pom.xml ] && eco maven
    { [ -f build.gradle ] || [ -f build.gradle.kts ]; } && eco gradle
    [ -f composer.json ] && eco composer
    [ -f Package.swift ] && eco swift
    [ -f Gemfile ] && eco bundler
    true # keep set -e happy when the last test is false
  } > .github/dependabot.yml

  git checkout -b "$BRANCH"
  git add .github
  git commit -q -m "Add security pipeline: OWASP scanning on every push

Calls the central reusable workflow in $OWNER/security-pipeline:
Semgrep (OWASP Top 10), Gitleaks, Trivy, CodeQL (public repos),
and optional Claude autofix PRs. Also configures Dependabot."
  git push -q -u origin "$BRANCH"

  gh pr create --repo "$OWNER/$REPO" \
    --head "$BRANCH" \
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
