#!/usr/bin/env bash
# Tests for pstack/bin/pstack-seat against fake codex and grok CLIs. Run from anywhere. Needs node.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
seat="$root/pstack/bin/pstack-seat"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/pstack-seat-test.XXXXXX")
tmp=$(cd "$tmp" && pwd -P)
marker="pstack-seat-test-$$"
cleanup() {
	pkill -f "$marker" 2>/dev/null
	rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p "$tmp/bin" "$tmp/repo"
cat >"$tmp/bin/codex" <<EOF
#!/bin/bash
printf '%s\n' "\$@" >"$tmp/codex.args"
out="" cwd="" json=0
while [ \$# -gt 0 ]; do
	case "\$1" in -o) out=\$2; shift ;; -C) cwd=\$2; shift ;; --json) json=1 ;; esac
	shift
done
cat >/dev/null
case "\${FAKE_MODE:-ok}" in
ok)
	echo "fake codex answer" >"\$out"
	if [ "\${FAKE_WRITE:-}" = 1 ]; then echo change >"\$cwd/new-file.txt"; fi
	if [ "\$json" = 1 ]; then
		echo '{"type":"thread.started","thread_id":"t-1"}'
		echo '{"type":"error","message":"stream dropped, retrying"}'
		echo '{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"fake codex answer"}}'
		echo '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":7,"reasoning_output_tokens":3}}'
	fi
	;;
fail) echo "codex: model not found" >&2; exit 3 ;;
turn-failed) echo '{"type":"turn.failed","error":{"message":"usage limit reached"}}'; exit 1 ;;
hang) bash -c 'exec -a $marker-grandchild sleep 600' & sleep 600 ;;
esac
EOF
cat >"$tmp/bin/grok" <<EOF
#!/bin/bash
printf '%s\n' "\$@" >"$tmp/grok.args"
pwd >"$tmp/grok.cwd"
model="" format=""
while [ \$# -gt 0 ]; do
	case "\$1" in -m) model=\$2; shift ;; --output-format) format=\$2; shift ;; esac
	shift
done
served=\${FAKE_SERVED:-\$model-build}
result() {
	printf '{"type":"system","subtype":"init","model":"%s"}\n' "\$model"
	printf '{"type":"result","subtype":"%s","is_error":%s,"result":"%s","total_cost_usd":0.25,"session_id":"s-1","usage":{"input_tokens":50,"cache_read_input_tokens":10,"output_tokens":5},"modelUsage":{"%s":{"inputTokens":50}}}\n' "\$1" "\$2" "\$3" "\$served"
}
case "\${FAKE_MODE:-ok}" in
ok) if [ "\$format" = plain ]; then echo "fake grok answer"; else result success false "fake grok answer"; fi ;;
error) result error_during_execution true "rate limited, try later" ;;
garbage) echo "not json at all" ;;
hang) bash -c 'exec -a $marker-grandchild sleep 600' & sleep 600 ;;
esac
EOF
chmod +x "$tmp/bin/codex" "$tmp/bin/grok"
export PATH="$tmp/bin:$PATH"

git -C "$tmp/repo" init -q
git -C "$tmp/repo" -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m init
tmp_note=""
case "$tmp/" in /tmp/* | /private/tmp/*) tmp_note=" note=repository-under-tmp-is-writable-by-grok" ;; esac
git -C "$tmp/repo" worktree add -q "$tmp/wt" -b wt 2>/dev/null

failures=0
check() {
	if [ "$2" = "$3" ]; then
		echo "ok   $1"
	else
		echo "FAIL $1"
		printf '  expected: %s\n  actual:   %s\n' "$2" "$3"
		failures=$((failures + 1))
	fi
}
contains() {
	case "$3" in *"$2"*) echo "ok   $1" ;; *)
		echo "FAIL $1"
		printf '  expected to contain: %s\n  actual: %s\n' "$2" "$3"
		failures=$((failures + 1))
		;;
	esac
}
new_prompt() {
	local d
	d=$(mktemp -d "$tmp/seat.XXXXXX")
	echo "Review the repository." >"$d/prompt.md"
	echo "$d"
}
# Prints one receipt field by dotted path: strings as they are, anything else as JSON.
field() {
	node -e 'const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
		const v = process.argv[2].split(".").reduce((o, k) => (o == null ? o : o[k]), r);
		console.log(typeof v === "string" ? v : JSON.stringify(v));' "$1" "$2"
}

d=$(new_prompt)
out=$(cd "$tmp/repo" && "$seat" --cli codex --model m1 --effort high --mode review --repo "$tmp/repo" --prompt "$d/prompt.md")
check "codex review succeeds" "codex-bridge: model=m1 effort=high mode=review exit=0 answer=$d/answer.md bytes=18 receipt=$d/receipt.json" "$out"
args=$(tr '\n' ' ' <"$tmp/codex.args")
contains "codex review is read-only on the repository" "-s read-only --skip-git-repo-check --ephemeral --color never -C $tmp/repo" "$args"
contains "codex gets the effort" "-c model_reasoning_effort=high" "$args"
contains "codex prints JSON events" "--json -" "$args"
check "codex receipt is complete" "complete" "$(field "$d/receipt.json" status)"
check "codex does not report its model" "not-reported" "$(field "$d/receipt.json" model_check)"
check "codex receipt keeps the requested model" "m1" "$(field "$d/receipt.json" model)"
check "codex receipt has the usage" '{"input":100,"cached_input":40,"output":7,"reasoning":3}' "$(field "$d/receipt.json" usage)"
check "codex receipt has the thread" "t-1" "$(field "$d/receipt.json" session_id)"
check "a recovered codex error does not fail the seat" "null" "$(field "$d/receipt.json" error)"
check "the receipt is private" "600" "$(node -e 'console.log((require("fs").statSync(process.argv[1]).mode & 0o777).toString(8))' "$d/receipt.json")"

d=$(new_prompt)
out=$(FAKE_MODE=fail "$seat" --cli codex --model m1 --mode review --repo "$tmp/repo" --prompt "$d/prompt.md")
check "a failing CLI reports its exit code and log" "codex-bridge: FAILED exit=3 bytes=0: codex: model not found receipt=$d/receipt.json" "$out"
check "a failed seat still writes its receipt" "failed" "$(field "$d/receipt.json" status)"

d=$(new_prompt)
out=$(FAKE_MODE=turn-failed "$seat" --cli codex --model m1 --mode review --repo "$tmp/repo" --prompt "$d/prompt.md")
check "a failed codex turn reports codex's reason" "codex-bridge: FAILED exit=1 bytes=0: usage limit reached receipt=$d/receipt.json" "$out"

d=$(new_prompt)
start=$(date +%s)
out=$(FAKE_MODE=hang "$seat" --cli codex --model m1 --mode review --repo "$tmp/repo" --prompt "$d/prompt.md" --deadline 2)
took=$(($(date +%s) - start))
contains "a hung codex stops at the deadline" "codex-bridge: FAILED deadline=2s: codex was stopped at its --deadline." "$out"
check "the deadline returns promptly" "yes" "$([ "$took" -le 8 ] && echo yes || echo "no, ${took}s")"
check "a stopped seat's receipt says deadline" "deadline" "$(field "$d/receipt.json" status)"
sleep 1
check "the CLI's whole process group is gone" "0" "$(pgrep -f "$marker-grandchild" | wc -l | tr -d ' ')"

d=$(new_prompt)
out=$(FAKE_MODE=hang BASH_MAX_TIMEOUT_MS=4000 "$seat" --cli grok --model g1 --mode review --repo "$tmp/repo" --prompt "$d/prompt.md")
contains "the default deadline follows BASH_MAX_TIMEOUT_MS, grok included" "grok-bridge: FAILED deadline=2s: grok was stopped before the Bash timeout." "$out"
sleep 1
check "grok's process group is gone too" "0" "$(pgrep -f "$marker-grandchild" | wc -l | tr -d ' ')"

d=$(new_prompt)
out=$("$seat" --cli grok --model g1 --effort low --mode review --repo "$tmp/repo" --prompt "$d/prompt.md")
check "grok review succeeds, noting a repository under /tmp" "grok-bridge: model=g1 effort=low mode=review exit=0 answer=$d/answer.md bytes=17 reported_model=g1-build receipt=$d/receipt.json$tmp_note" "$out"
check "grok's answer is the result event's text" "fake grok answer" "$(cat "$d/answer.md")"
check "grok review runs from a scratch directory" "$d/cwd" "$(cat "$tmp/grok.cwd")"
contains "grok review keeps MCP gateways and edits out" "--disallowed-tools search_replace,search_tool,use_tool" "$(tr '\n' ' ' <"$tmp/grok.args")"
contains "grok prints JSON events" "--output-format streaming-messages-json" "$(tr '\n' ' ' <"$tmp/grok.args")"
contains "grok review prompt names the repository" "The repository for this task is at $tmp/repo." "$(cat "$d/prompt.grok.md")"
check "a build of the requested grok model counts as a match" "match" "$(field "$d/receipt.json" model_check)"
check "grok receipt has the cost" "0.25" "$(field "$d/receipt.json" cost_usd)"
check "grok receipt has the usage" '{"input":50,"cached_input":10,"output":5,"reasoning":null}' "$(field "$d/receipt.json" usage)"

d=$(new_prompt)
out=$(FAKE_SERVED=g0 "$seat" --cli grok --model g1 --mode review --repo "$tmp/repo" --prompt "$d/prompt.md")
contains "another served model is noted, not failed" "exit=0 answer=$d/answer.md bytes=17 reported_model=g0 receipt=$d/receipt.json$tmp_note note=model-mismatch" "$out"
check "the mismatch is in the receipt" "mismatch" "$(field "$d/receipt.json" model_check)"

d=$(new_prompt)
out=$(FAKE_MODE=error "$seat" --cli grok --model g1 --mode review --repo "$tmp/repo" --prompt "$d/prompt.md")
check "a grok error result fails the seat with grok's reason" "grok-bridge: FAILED exit=0 bytes=0: rate limited, try later reported_model=g1-build receipt=$d/receipt.json" "$out"

d=$(new_prompt)
out=$(FAKE_MODE=garbage "$seat" --cli grok --model g1 --mode review --repo "$tmp/repo" --prompt "$d/prompt.md")
check "grok output with no result event fails the seat" "grok-bridge: FAILED exit=0 bytes=0: grok printed no result event receipt=$d/receipt.json" "$out"

d=$(new_prompt)
out=$(cd "$tmp/repo" && "$seat" --cli codex --model m1 --mode write --repo "$tmp/repo" --prompt "$d/prompt.md")
check "write outside a linked worktree runs as review" "codex-bridge: model=m1 effort=default mode=review exit=0 answer=$d/answer.md bytes=18 receipt=$d/receipt.json note=write-refused-not-in-a-linked-worktree" "$out"
check "the receipt records the mode the seat ran in" "review" "$(field "$d/receipt.json" mode)"
check "the receipt keeps the seat's notes" '["write-refused-not-in-a-linked-worktree"]' "$(field "$d/receipt.json" notes)"

d=$(new_prompt)
out=$(cd "$tmp/wt" && FAKE_WRITE=1 "$seat" --cli codex --model m1 --mode write --repo "$tmp/repo" --prompt "$d/prompt.md")
check "write inside a linked worktree writes there and lists the change" "codex-bridge: model=m1 effort=default mode=write exit=0 answer=$d/answer.md bytes=18 receipt=$d/receipt.json
?? new-file.txt" "$out"
check "a write seat's receipt says write" "write" "$(field "$d/receipt.json" mode)"

# Without node the seat runs as before: plain Grok output and no receipt.
mkdir -p "$tmp/nonode"
for tool in bash env git mkdir rm cat wc tr tail cut sed sleep dirname date; do
	ln -s "$(command -v "$tool")" "$tmp/nonode/$tool"
done
ln -s "$tmp/bin/grok" "$tmp/nonode/grok"
d=$(new_prompt)
out=$(PATH="$tmp/nonode" "$seat" --cli grok --model g1 --mode review --repo "$tmp/repo" --prompt "$d/prompt.md")
check "without node grok still answers, with no receipt" "grok-bridge: model=g1 effort=default mode=review exit=0 answer=$d/answer.md bytes=17$tmp_note" "$out"
contains "without node grok prints plain text" "--output-format plain" "$(tr '\n' ' ' <"$tmp/grok.args")"
check "without node no receipt is written" "no" "$([ -e "$d/receipt.json" ] && echo yes || echo no)"

d=$(new_prompt)
out=$("$seat" --cli codex --model m1 --mode review --repo "$tmp/repo" --prompt "$d/prompt.md" --deadline soon)
check "a non-numeric deadline is refused" "codex-bridge: FAILED --deadline must be a number of seconds" "$out"

out=$("$seat" --cli cursor --model m1 --prompt /nonexistent)
check "an unknown CLI is refused" "pstack-seat: FAILED --cli must be codex or grok" "$out"

[ "$failures" -eq 0 ] || {
	echo "$failures failed"
	exit 1
}
echo "all passed"
