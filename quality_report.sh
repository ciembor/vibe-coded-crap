#!/bin/sh

set -u

TMP_DIR="tmp"
REEK_JSON="$TMP_DIR/reek-report.json"
QUALITY_JSON="$TMP_DIR/quality-report.json"

mkdir -p "$TMP_DIR"

if ! command -v jq >/dev/null 2>&1; then
  echo "Brakuje jq. Zainstaluj jq, np.:" >&2
  echo "  brew install jq" >&2
  echo "  sudo apt install jq" >&2
  exit 1
fi

TARGETS=""

if [ "$#" -gt 0 ]; then
  for path in "$@"; do
    if [ -e "$path" ]; then
      TARGETS="$TARGETS $path"
    else
      echo "Pomijam nieistniejącą ścieżkę: $path" >&2
    fi
  done
else
  for path in lib bin; do
    if [ -e "$path" ]; then
      TARGETS="$TARGETS $path"
    fi
  done
fi

if [ -z "$TARGETS" ]; then
  echo "Nie znaleziono katalogów do analizy. Podaj np.:" >&2
  echo "quality_report.sh lib bin" >&2
  exit 1
fi

echo "$ bundle exec rspec" >&2
bundle exec rspec >&2
RSPEC_STATUS=$?

COVERAGE="null"

if [ -f "coverage/.last_run.json" ]; then
  COVERAGE=$(jq -r '
    if .result.line then
      .result.line
    elif .result.covered_percent then
      .result.covered_percent
    else
      "null"
    end
  ' coverage/.last_run.json)
fi

if [ "$COVERAGE" = "null" ] && [ -f "coverage/.resultset.json" ]; then
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
        | floor
      )
    end
  ' coverage/.resultset.json)
fi

echo "$ bundle exec reek --list" >&2

ALL_REEK_SMELLS=$(
  bundle exec reek --list |
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

echo "$ bundle exec reek --format=json$TARGETS" >&2

# shellcheck disable=SC2086
bundle exec reek --format=json $TARGETS > "$REEK_JSON"
REEK_STATUS=$?

SMELLS_BY_TYPE=$(jq --argjson all_smells "$ALL_REEK_SMELLS" '
  ($all_smells | map({ key: ., value: 0 }) | from_entries) as $defaults
  |
  (
    group_by(.smell_type)
    | map({
        key: .[0].smell_type,
        value: length
      })
    | from_entries
  ) as $actual
  |
  $defaults + $actual
' "$REEK_JSON")

SMELLS_TOTAL=$(echo "$SMELLS_BY_TYPE" | jq '[.[]] | add')

cat > "$QUALITY_JSON" <<EOF
{
  "coverage_percent": $COVERAGE,
  "smells_total": $SMELLS_TOTAL,
  "smells_by_type": $SMELLS_BY_TYPE
}
EOF

cat "$QUALITY_JSON"

exit "$RSPEC_STATUS"
