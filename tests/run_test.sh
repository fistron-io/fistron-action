#!/usr/bin/env bash
# run.sh with a fake docker: the configuration it writes, the names it passes
# (never a value), the inputs it turns into options.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "${tmp:?}"' EXIT
mkdir -p "$tmp/bin" "$tmp/workspace" "$tmp/temp"
cat > "$tmp/bin/docker" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_DOCKER_ARGS"
FAKE
chmod +x "$tmp/bin/docker"

run() {
  env -i PATH="$tmp/bin:/usr/bin:/bin" HOME="$tmp" FAKE_DOCKER_ARGS="$tmp/args" \
    GITHUB_WORKSPACE="$tmp/workspace" RUNNER_TEMP="$tmp/temp" \
    GITHUB_API_URL=https://api.github.com GITHUB_REPOSITORY=jana/shop \
    FISTRON_IMAGE=ghcr.io/fistron-io/fistron-core@sha256:abc \
    FISTRON_GITHUB_TOKEN=secret-token FISTRON_LLM_API_KEY=secret-key \
    "$@" bash "$here/run.sh"
}
fail() { echo "FAIL: $*" >&2; exit 1; }

run FISTRON_VERIFY='pytest {tests}' FISTRON_PUBLISH=true FISTRON_DAILY_CAP_EUR=2
args="$(cat "$tmp/args")"
config="$(cat "$tmp/temp/fistron/fistron.toml")"
grep -qx -- '--verify' <<<"$args" || fail "no --verify"
grep -qx -- 'pytest {tests}' <<<"$args" || fail "the verify command"
grep -qx -- '--publish' <<<"$args" || fail "no --publish"
grep -qx -- '--daily-cap-eur' <<<"$args" || fail "no --daily-cap-eur"
grep -qx -- 'ghcr.io/fistron-io/fistron-core@sha256:abc' <<<"$args" || fail "the image"
grep -qx -- 'ACTIONS_ID_TOKEN_REQUEST_TOKEN' <<<"$args" || fail "the identity token's names"
if grep -q 'secret-token\|secret-key' <<<"$args"; then fail "a value on docker's command line"; fi
if grep -q 'secret' <<<"$config"; then fail "a value in the configuration"; fi
grep -q '"propose-code-fix" = "propose"' <<<"$config" || fail "the fix's action"
if grep -q '\[llm\]' <<<"$config"; then fail "an own model without its URL"; fi
grep -q 'fistron ci-fix "\$@"' "$tmp/temp/fistron/inside.sh" || fail "the inside script"

run FISTRON_PUBLISH=false FISTRON_MODEL_BASE_URL=https://llm.example.test/v1 FISTRON_MODEL_NAME=m
args="$(cat "$tmp/args")"
config="$(cat "$tmp/temp/fistron/fistron.toml")"
if grep -qx -- '--publish' <<<"$args"; then fail "--publish when false"; fi
if grep -qx -- '--verify' <<<"$args"; then fail "--verify without a command"; fi
grep -q 'base_url = "https://llm.example.test/v1"' <<<"$config" || fail "the own model"
grep -q 'api_key_env = "FISTRON_LLM_API_KEY"' <<<"$config" || fail "the key's variable"
grep -q 'repair = "own"' <<<"$config" || fail "the role repair"
run FISTRON_VERIFY_WORKFLOW=ci.yml FISTRON_HEAD_BRANCH=fistron/verify/abc-g1
args="$(cat "$tmp/args")"
grep -qx -- '--verify-workflow' <<<"$args" || fail "no --verify-workflow"
grep -qx -- 'FISTRON_HEAD_BRANCH' <<<"$args" || fail "the head branch's name"
grep -q 'fistron/verify/\*)' "$tmp/temp/fistron/inside.sh" || fail "the verdict's branch"
echo "run.sh: all checks passed"
