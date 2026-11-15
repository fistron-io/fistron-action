#!/usr/bin/env bash
# Fistron in a failed run's trusted workflow (Fistron ADR 0171): the run's
# licence for its identity token, the failed jobs imported, every cause, the
# fixes verified and the comment, all in Fistron's image. Every input comes
# through the environment (action.yml); nothing here prints a token.
set -euo pipefail

: "${FISTRON_IMAGE:?the image}"
: "${GITHUB_WORKSPACE:?run in GitHub Actions}"
: "${RUNNER_TEMP:?run in GitHub Actions}"
work="$RUNNER_TEMP/fistron"
mkdir -p "$work"
config="$work/fistron.toml"

# the configuration: reading the run, and writing only the fix's action
{
  printf '[acquisition.github]\nbase_url = "%s"\ntoken_env = "FISTRON_GITHUB_TOKEN"\n' "$GITHUB_API_URL"
  printf 'repositories = ["%s"]\n\n' "$GITHUB_REPOSITORY"
  printf '[actions.github]\nbase_url = "%s"\ntoken_env = "FISTRON_GITHUB_TOKEN"\n' "$GITHUB_API_URL"
  printf 'repositories = ["%s"]\n\n[actions.github.allow]\n"propose-code-fix" = "propose"\n' "$GITHUB_REPOSITORY"
  if [ -n "${FISTRON_MODEL_BASE_URL:-}" ]; then
    # the person's own model: the roles that call one
    printf '\n[llm]\ndefault_data_class = "confidential"\n\n[llm.endpoints.own]\n'
    printf 'base_url = "%s"\nmodel = "%s"\napi = "%s"\n' \
      "$FISTRON_MODEL_BASE_URL" "${FISTRON_MODEL_NAME:-}" "${FISTRON_MODEL_API:-chat}"
    printf 'max_data_class = "confidential"\napi_key_env = "FISTRON_LLM_API_KEY"\n\n'
    printf '[llm.roles]\nreasoner = "own"\nrepair = "own"\n'
  fi
} > "$config"

args=(--ci-output "$work/report" --repository .fistron-repository --state .fistron-ci
      --run-file "$work/fistron-run.json" --config "$config" --output "$work/ci-fix")
if [ -n "${FISTRON_VERIFY:-}" ]; then args+=(--verify "$FISTRON_VERIFY"); fi
if [ -n "${FISTRON_VERIFY_WORKFLOW:-}" ]; then
  args+=(--verify-workflow "$FISTRON_VERIFY_WORKFLOW")
fi
if [ "${FISTRON_PUBLISH:-true}" = "true" ]; then args+=(--publish); fi
if [ -n "${FISTRON_DAILY_CAP_EUR:-}" ]; then args+=(--daily-cap-eur "$FISTRON_DAILY_CAP_EUR"); fi
if [ -n "${FISTRON_MONTHLY_CAP_EUR:-}" ]; then args+=(--monthly-cap-eur "$FISTRON_MONTHLY_CAP_EUR"); fi

# the names only: docker reads the values from this step's environment
envs=(GITHUB_ACTIONS GITHUB_API_URL GITHUB_REPOSITORY GITHUB_SHA GITHUB_RUN_ID
      GITHUB_EVENT_PATH GITHUB_EVENT_NAME GITHUB_STEP_SUMMARY RUNNER_TEMP
      ACTIONS_ID_TOKEN_REQUEST_URL ACTIONS_ID_TOKEN_REQUEST_TOKEN
      FISTRON_GITHUB_TOKEN FISTRON_LLM_API_KEY FISTRON_CP_URL FISTRON_RUN_ID
      FISTRON_HEAD_BRANCH)
docker_env=()
for name in "${envs[@]}"; do docker_env+=(-e "$name"); done

# inside: the licence set for this shell alone, then the run; Fistron never
# fails the build, so neither does this step
cat > "$work/inside.sh" <<'INSIDE'
set -uo pipefail
work="$1"
shift
case "${FISTRON_HEAD_BRANCH:-}" in
  fistron/verify/*)
    # the run of a fix's verification ended: its verdict, no analysis, no model
    fistron ci-fix "$@" || true
    exit 0
    ;;
esac
eval "$(fistron ci-licence --export --run-file "$work/fistron-run.json")" || true
fistron ci --config "$work/fistron.toml" --output "$work/report" --run "$FISTRON_RUN_ID" || true
fistron ci-fix "$@" || true
INSIDE

docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp "${docker_env[@]}" \
  -v "$GITHUB_WORKSPACE:$GITHUB_WORKSPACE" -v "$RUNNER_TEMP:$RUNNER_TEMP" \
  -w "$GITHUB_WORKSPACE" --entrypoint bash "$FISTRON_IMAGE" \
  "$work/inside.sh" "$work" "${args[@]}"
