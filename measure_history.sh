#!/bin/sh

set -u

TARGET_COMMIT="${1:-9213af17baec9f5235f4649b86aa7613a721b88e}"

REPO_ROOT="$(git rev-parse --show-toplevel)"
TOOL_BUNDLE_GEMFILE="$REPO_ROOT/Gemfile"

DEFAULT_TARGETS="${TARGETS:-lib bin}"
RUN_SPECS="${RUN_SPECS:-1}"

SHORT_TARGET="$(git -C "$REPO_ROOT" rev-parse --short "$TARGET_COMMIT")"
RUN_ID="$(date '+%Y-%m-%d_%H-%M-%S')"

REPORT_DIR="$REPO_ROOT/reports/history-$SHORT_TARGET-$RUN_ID"
COMMITS_DIR="$REPORT_DIR/commits"
LOGS_DIR="$REPORT_DIR/logs"
COVERAGE_DIR="$REPORT_DIR/coverage"

SUMMARY_CSV="$REPORT_DIR/measurements.csv"
SMELLS_CSV="$REPORT_DIR/measurements_by_smell.csv"
JSONL="$REPORT_DIR/measurements.jsonl"

mkdir -p "$COMMITS_DIR" "$LOGS_DIR" "$COVERAGE_DIR"

if ! command -v jq >/dev/null 2>&1; then
  echo "Brakuje jq. Zainstaluj jq, np.:" >&2
  echo "  brew install jq" >&2
  echo "  sudo apt install jq" >&2
  exit 1
fi

if ! command -v bundle >/dev/null 2>&1; then
  echo "Brakuje Bundlera: bundle" >&2
  exit 1
fi

if [ ! -f "$TOOL_BUNDLE_GEMFILE" ]; then
  echo "Nie znaleziono Gemfile: $TOOL_BUNDLE_GEMFILE" >&2
  exit 1
fi

echo "Sprawdzam aktualny bundle..." >&2

(
  cd "$REPO_ROOT" &&
  BUNDLE_GEMFILE="$TOOL_BUNDLE_GEMFILE" bundle check >/dev/null 2>&1 ||
  BUNDLE_GEMFILE="$TOOL_BUNDLE_GEMFILE" bundle install
)

SIMPLECOV_BOOTSTRAP="$REPORT_DIR/simplecov_bootstrap.rb"

cat > "$SIMPLECOV_BOOTSTRAP" <<'RUBY'
require 'simplecov'

SimpleCov.root Dir.pwd
SimpleCov.coverage_dir ENV.fetch('SIMPLECOV_COVERAGE_DIR', 'coverage')
SimpleCov.command_name ENV.fetch('SIMPLECOV_COMMAND_NAME', 'RSpec')

SimpleCov.start do
  add_filter '/spec/'
  add_filter '/test/'
  add_filter '/coverage/'
  add_filter '/tmp/'
  add_filter '/reports/'
end
RUBY

echo "Pobieram listę code smells z Reeka..." >&2

ALL_REEK_SMELLS=$(
  (
    cd "$REPO_ROOT" &&
    BUNDLE_GEMFILE="$TOOL_BUNDLE_GEMFILE" bundle exec reek --list
  ) |
    sed -n '
      s/^[[:space:]]*[-*]*[[:space:]]*\([A-Z][A-Za-z0-9]*\)[[:space:]]*$/\1/p
      s/^[[:space:]]*[-*]*[[:space:]]*\([A-Z][A-Za-z0-9]*\)[[:space:]:].*$/\1/p
    ' |
    sort -u |
    jq -R -s '
      split("\n")
      | map(select(length > 0))
    '
)

TMP_PARENT="$(mktemp -d)"
WORKTREE="$TMP_PARENT/worktree"

cleanup() {
  git -C "$REPO_ROOT" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
  rm -rf "$TMP_PARENT"
}

trap cleanup EXIT INT TERM

git -C "$REPO_ROOT" worktree add --detach "$WORKTREE" "$TARGET_COMMIT" >/dev/null

echo "commit_number,commit,short_commit,committed_at,coverage_percent,smells_total,rspec_exit_status,reek_exit_status,subject" > "$SUMMARY_CSV"
echo "commit_number,commit,short_commit,committed_at,smell,count" > "$SMELLS_CSV"
: > "$JSONL"

COMMITS="$(git -C "$REPO_ROOT" rev-list --reverse "$TARGET_COMMIT")"
TOTAL="$(echo "$COMMITS" | wc -l | tr -d ' ')"
CURRENT=0

for COMMIT in $COMMITS; do
  CURRENT=$((CURRENT + 1))

  SHORT_COMMIT="$(git -C "$REPO_ROOT" rev-parse --short "$COMMIT")"
  COMMITTED_AT="$(git -C "$REPO_ROOT" show -s --format=%cI "$COMMIT")"
  SUBJECT="$(git -C "$REPO_ROOT" show -s --format=%s "$COMMIT")"

  RAW_REEK_JSON="$COMMITS_DIR/$SHORT_COMMIT.reek.raw.json"
  FINAL_JSON="$COMMITS_DIR/$SHORT_COMMIT.json"
  LOG_FILE="$LOGS_DIR/$SHORT_COMMIT.log"
  RSPEC_LOG="$LOGS_DIR/$SHORT_COMMIT.rspec.log"
  COMMIT_COVERAGE_DIR="$COVERAGE_DIR/$SHORT_COMMIT"

  mkdir -p "$COMMIT_COVERAGE_DIR"
  : > "$LOG_FILE"
  : > "$RSPEC_LOG"

  echo "[$CURRENT/$TOTAL] Measuring $SHORT_COMMIT - $SUBJECT" >&2

  git -C "$WORKTREE" checkout --quiet --detach "$COMMIT"

  EXISTING_TARGETS=""

  for path in $DEFAULT_TARGETS; do
    if [ -e "$WORKTREE/$path" ]; then
      EXISTING_TARGETS="$EXISTING_TARGETS $WORKTREE/$path"
    else
      echo "Pomijam nieistniejącą ścieżkę w $SHORT_COMMIT: $path" >> "$LOG_FILE"
    fi
  done

  RSPEC_EXIT_STATUS=0
  COVERAGE="null"

  if [ "$RUN_SPECS" = "1" ]; then
    if [ -d "$WORKTREE/spec" ]; then
      RUBYOPT_VALUE="-r$SIMPLECOV_BOOTSTRAP"

      if [ "${RUBYOPT:-}" != "" ]; then
        RUBYOPT_VALUE="$RUBYOPT_VALUE $RUBYOPT"
      fi

      (
        cd "$WORKTREE" &&
        BUNDLE_GEMFILE="$TOOL_BUNDLE_GEMFILE" \
        SIMPLECOV_COVERAGE_DIR="$COMMIT_COVERAGE_DIR" \
        SIMPLECOV_COMMAND_NAME="RSpec $SHORT_COMMIT" \
        RUBYOPT="$RUBYOPT_VALUE" \
        RUBYLIB="$WORKTREE/lib${RUBYLIB:+:$RUBYLIB}" \
        bundle exec rspec > "$RSPEC_LOG" 2>> "$LOG_FILE"
      )

      RSPEC_EXIT_STATUS=$?
    else
      echo "Brak katalogu spec w $SHORT_COMMIT — pomijam testy." >> "$LOG_FILE"
      RSPEC_EXIT_STATUS=0
    fi

    if [ -f "$COMMIT_COVERAGE_DIR/.last_run.json" ]; then
      COVERAGE=$(jq -r '
        if .result.line then
          .result.line
        elif .result.covered_percent then
          .result.covered_percent
        else
          "null"
        end
      ' "$COMMIT_COVERAGE_DIR/.last_run.json")
    fi

    if [ "$COVERAGE" = "null" ] && [ -f "$COMMIT_COVERAGE_DIR/.resultset.json" ]; then
      COVERAGE=$(jq -r '
        [
          .[]
          | .coverage
          | to_entries[]
          | .value
          | if type == "object" then .lines else . end
          | .[]
          | select(. != null)
        ] as $lines
        |
        if ($lines | length) == 0 then
          "null"
        else
          (
            (($lines | map(select(. > 0)) | length) / ($lines | length) * 100)
            | .*100
            | round
            | ./100
          )
        end
      ' "$COMMIT_COVERAGE_DIR/.resultset.json")
    fi
  fi

  REEK_EXIT_STATUS=0

  if [ -n "$EXISTING_TARGETS" ]; then
    (
      cd "$REPO_ROOT" &&
      # shellcheck disable=SC2086
      BUNDLE_GEMFILE="$TOOL_BUNDLE_GEMFILE" bundle exec reek --format=json $EXISTING_TARGETS > "$RAW_REEK_JSON" 2>> "$LOG_FILE"
    )

    REEK_EXIT_STATUS=$?
  else
    echo "[]" > "$RAW_REEK_JSON"
    echo "Brak ścieżek do analizy Reekiem." >> "$LOG_FILE"
    REEK_EXIT_STATUS=0
  fi

  if ! jq empty "$RAW_REEK_JSON" >/dev/null 2>&1; then
    echo "Reek nie zwrócił poprawnego JSON-a. Zapisuję pustą listę smelli." >> "$LOG_FILE"
    echo "[]" > "$RAW_REEK_JSON"
  fi

  SMELLS_BY_TYPE=$(jq --argjson all_smells "$ALL_REEK_SMELLS" '
    ($all_smells | map({ key: ., value: 0 }) | from_entries) as $defaults
    |
    (
      [
        .[]
        | select((.is_active // true) != false)
        | select((.status.is_active // true) != false)
        | (
            .smell_type
            // .smell.subclass
            // .smell.class
            // .class
            // "Unknown"
          )
      ]
      | group_by(.)
      | map({
          key: .[0],
          value: length
        })
      | from_entries
    ) as $actual
    |
    $defaults + $actual
  ' "$RAW_REEK_JSON")

  SMELLS_TOTAL=$(echo "$SMELLS_BY_TYPE" | jq '[.[]] | add // 0')

  jq -n \
    --argjson commit_number "$CURRENT" \
    --arg commit "$COMMIT" \
    --arg short_commit "$SHORT_COMMIT" \
    --arg committed_at "$COMMITTED_AT" \
    --arg subject "$SUBJECT" \
    --argjson coverage_percent "$COVERAGE" \
    --argjson smells_total "$SMELLS_TOTAL" \
    --argjson smells_by_type "$SMELLS_BY_TYPE" \
    --argjson rspec_exit_status "$RSPEC_EXIT_STATUS" \
    --argjson reek_exit_status "$REEK_EXIT_STATUS" \
    '
    {
      commit_number: $commit_number,
      commit: $commit,
      short_commit: $short_commit,
      committed_at: $committed_at,
      subject: $subject,
      coverage_percent: $coverage_percent,
      smells_total: $smells_total,
      smells_by_type: $smells_by_type,
      rspec_exit_status: $rspec_exit_status,
      reek_exit_status: $reek_exit_status
    }
    ' > "$FINAL_JSON"

  cat "$FINAL_JSON" >> "$JSONL"
  echo >> "$JSONL"

  jq -r '
    [
      .commit_number,
      .commit,
      .short_commit,
      .committed_at,
      .coverage_percent,
      .smells_total,
      .rspec_exit_status,
      .reek_exit_status,
      .subject
    ] | @csv
  ' "$FINAL_JSON" >> "$SUMMARY_CSV"

  jq -r '
    . as $root
    | .smells_by_type
    | to_entries[]
    | [
        $root.commit_number,
        $root.commit,
        $root.short_commit,
        $root.committed_at,
        .key,
        .value
      ] | @csv
  ' "$FINAL_JSON" >> "$SMELLS_CSV"
done

echo
echo "Gotowe."
echo "Raport:"
echo "  $REPORT_DIR"
echo
echo "Pliki:"
echo "  $SUMMARY_CSV"
echo "  $SMELLS_CSV"
echo "  $JSONL"
echo "  $COMMITS_DIR"
echo "  $LOGS_DIR"
echo
echo "Jeśli measurements.csv ma teraz liczby w smells_total, możesz wysłać mi:"
echo "  $SUMMARY_CSV"
echo "  $SMELLS_CSV"
