#!/usr/bin/env bash
# Drain the Dependabot backlog: merge every open Dependabot PR that is
#   (a) a minor or patch bump (majors and 0.x minors are left for review), and
#   (b) fully green (all checks passed).
# Usage: ./drain.sh            # dry run — prints what it would merge
#        ./drain.sh --merge    # actually merge (squash)
set -euo pipefail
OWNER="rafaktor"
DO_MERGE="${1:-}"

gh search prs --owner "$OWNER" --state open --author app/dependabot --limit 100 \
  --json repository,number,title \
  --jq '.[] | "\(.repository.nameWithOwner)\t\(.number)\t\(.title)"' |
while IFS=$'\t' read -r REPO NUM TITLE; do
  # Our dependabot groups only ever contain minor+patch bumps, so grouped
  # PRs are safe by construction; otherwise require an explicit "from X to Y".
  if ! grep -qE -- '-minor-patch group' <<<"$TITLE"; then
    VERS=$(sed -nE 's/.*[Ff]rom ([0-9]+)\.([0-9]+)[^ ]* to ([0-9]+)\.([0-9]+).*/\1 \2 \3 \4/p' <<<"$TITLE")
    [ -z "$VERS" ] && { echo "SKIP  (no version)   $REPO#$NUM $TITLE"; continue; }
    read -r MA1 MI1 MA2 MI2 <<<"$VERS"
    if [ "$MA1" != "$MA2" ] || { [ "$MA1" = "0" ] && [ "$MI1" != "$MI2" ]; }; then
      echo "SKIP  (major/0.x)    $REPO#$NUM $TITLE"; continue
    fi
  fi
  STATE=$(gh pr view "$NUM" -R "$REPO" --json statusCheckRollup \
    --jq '[.statusCheckRollup[]?.conclusion // .statusCheckRollup[]?.state] | if length==0 then "NONE" elif all(.[]; .=="SUCCESS" or .=="NEUTRAL" or .=="SKIPPED") then "GREEN" else "RED" end')
  if [ "$STATE" != "GREEN" ]; then
    echo "SKIP  (checks $STATE) $REPO#$NUM $TITLE"; continue
  fi
  if [ "$DO_MERGE" = "--merge" ]; then
    gh pr merge "$NUM" -R "$REPO" --squash --delete-branch && echo "MERGED               $REPO#$NUM $TITLE"
  else
    echo "WOULD MERGE          $REPO#$NUM $TITLE"
  fi
done
if [ "$DO_MERGE" = "--merge" ]; then echo "Done."; else echo "Dry run done. Re-run with --merge to apply."; fi
