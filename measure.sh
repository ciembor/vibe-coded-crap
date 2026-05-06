#!/usr/bin/env bash
set -euo pipefail

TARGETS="${TARGETS:-app lib}"
RSPEC_CMD="${RSPEC_CMD:-bundle exec rspec --require spec_helper}"

BRANCH="$(git rev-parse --abbrev-ref HEAD | tr '/ ' '__')"
COMMIT="$(git rev-parse --short HEAD)"
TIMESTAMP="$(date +"%Y-%m-%d_%H-%M-%S")"

REPORT_ROOT="reports"
REPORT_DIR="$REPORT_ROOT/$BRANCH-$COMMIT-$TIMESTAMP"

mkdir -p "$REPORT_DIR"

echo "Branch: $BRANCH"
echo "Commit: $COMMIT"
echo "Report: $REPORT_DIR"

echo
echo "== Cleaning old coverage =="
rm -rf coverage

echo
echo "== Running specs with coverage =="
$RSPEC_CMD

echo
echo "== Checking coverage result =="
if [ ! -f "coverage/.resultset.json" ]; then
  echo "ERROR: coverage/.resultset.json was not created"
  echo "SimpleCov probably did not start correctly."
  exit 1
fi

cp -r coverage "$REPORT_DIR/coverage"

echo
echo "== Running RubyCritic =="
bundle exec rubycritic $TARGETS \
  --format json \
  --no-browser \
  --coverage-path coverage \
  --path "$REPORT_DIR/rubycritic"

echo
echo "== Writing metadata =="
cat > "$REPORT_DIR/meta.json" <<JSON
{
  "branch": "$BRANCH",
  "commit": "$COMMIT",
  "timestamp": "$TIMESTAMP",
  "targets": "$TARGETS",
  "rspec_command": "$RSPEC_CMD"
}
JSON

SUMMARY_CSV="$REPORT_ROOT/measurements.csv"

if [ ! -f "$SUMMARY_CSV" ]; then
  echo "branch,commit,timestamp,report_dir,coverage_file,rubycritic_dir" > "$SUMMARY_CSV"
fi

echo "$BRANCH,$COMMIT,$TIMESTAMP,$REPORT_DIR,$REPORT_DIR/coverage/.resultset.json,$REPORT_DIR/rubycritic" >> "$SUMMARY_CSV"

echo
echo "Done."
echo "Report saved to: $REPORT_DIR"
echo "Summary updated: $SUMMARY_CSV"
