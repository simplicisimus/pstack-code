#!/usr/bin/env bash
# Tests for pstack/bin/openrouter-ask against a local stub of the OpenRouter API. Run from anywhere. Needs node.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
ask="$root/pstack/bin/openrouter-ask"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/openrouter-ask-test.XXXXXX")
server=""
cleanup() {
	[ -n "$server" ] && { kill "$server" && wait "$server"; } 2>/dev/null
	rm -rf "$tmp"
}
trap cleanup EXIT

cat >"$tmp/stub.mjs" <<'EOF'
import { createServer } from "node:http";
import { writeFileSync } from "node:fs";
const served = { "vendor/good:free": "vendor/good", "openrouter/free": "vendor/picked", "vendor/other": "vendor/else" };
const server = createServer((req, res) => {
	let body = "";
	req.on("data", (chunk) => (body += chunk));
	req.on("end", () => {
		const { model } = JSON.parse(body);
		res.setHeader("Content-Type", "application/json");
		if (model === "vendor/broken") {
			res.statusCode = 503;
			res.end(JSON.stringify({ error: { message: "overloaded" } }));
			return;
		}
		res.end(JSON.stringify({
			id: "gen-1",
			model: served[model],
			choices: [{ message: { content: "stub answer" } }],
			usage: { prompt_tokens: 12, completion_tokens: 3, total_tokens: 15, cost: 0.5,
				prompt_tokens_details: { cached_tokens: 4 }, completion_tokens_details: { reasoning_tokens: 1 } },
		}));
	});
});
server.listen(0, "127.0.0.1", () => writeFileSync(process.argv[2], String(server.address().port)));
EOF
node "$tmp/stub.mjs" "$tmp/port" &
server=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
	[ -s "$tmp/port" ] && break
	sleep 0.2
done
export OPENROUTER_BASE_URL="http://127.0.0.1:$(cat "$tmp/port")"
export OPENROUTER_API_KEY=test-key
echo "Review this." >"$tmp/prompt.md"

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
field() {
	node -e 'const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
		const v = process.argv[2].split(".").reduce((o, k) => (o == null ? o : o[k]), r);
		console.log(typeof v === "string" ? v : JSON.stringify(v));' "$1" "$2"
}

out=$("$ask" --model vendor/good:free --prompt-file "$tmp/prompt.md" --receipt "$tmp/good.json" 2>"$tmp/good.err")
check "the answer goes to stdout" "stub answer" "$out"
check "stderr names the served model and the check" "openrouter-ask: model=vendor/good model_check=match tokens=15" "$(cat "$tmp/good.err")"
check "a :free variant matches its served model" "match" "$(field "$tmp/good.json" model_check)"
check "the receipt is complete" "complete" "$(field "$tmp/good.json" status)"
check "the receipt has the usage" '{"input":12,"cached_input":4,"output":3,"reasoning":1}' "$(field "$tmp/good.json" usage)"
check "the receipt has the cost" "0.5" "$(field "$tmp/good.json" cost_usd)"
check "the receipt has the answer's size" "12" "$(field "$tmp/good.json" bytes)"

"$ask" --model openrouter/free --prompt-file "$tmp/prompt.md" --receipt "$tmp/routed.json" >/dev/null 2>&1
check "a router id records the model it picked" "vendor/picked" "$(field "$tmp/routed.json" reported_model)"
check "a router id is routed, not a mismatch" "routed" "$(field "$tmp/routed.json" model_check)"

"$ask" --model vendor/other --prompt-file "$tmp/prompt.md" --receipt "$tmp/other.json" >/dev/null 2>&1
check "another served model is a mismatch" "mismatch" "$(field "$tmp/other.json" model_check)"

"$ask" --model vendor/broken --prompt-file "$tmp/prompt.md" --receipt "$tmp/broken.json" >/dev/null 2>&1
check "a failed request exits 1" "1" "$?"
check "a failed request still writes a receipt" "failed" "$(field "$tmp/broken.json" status)"
check "the receipt keeps the error" "HTTP 503: overloaded" "$(field "$tmp/broken.json" error)"

OPENROUTER_API_KEY="" "$ask" --model vendor/good --prompt-file "$tmp/prompt.md" --receipt "$tmp/nokey.json" >/dev/null 2>&1
check "a missing key writes a failed receipt" "OPENROUTER_API_KEY is not set" "$(field "$tmp/nokey.json" error)"

[ "$failures" -eq 0 ] || {
	echo "$failures failed"
	exit 1
}
echo "all passed"
