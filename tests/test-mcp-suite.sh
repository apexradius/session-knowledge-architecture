#!/bin/bash
# ============================================================================
# Apex Radius MCP Suite — Smoke Test
# Tests all 8 MCP servers: start, initialize handshake, tools/list, tool count
# Compatible with macOS bash 3.2+
# ============================================================================

set -eo pipefail

# --- Configuration -----------------------------------------------------------
SERVERS=(
  "apex-github-mcp:27"
  "apex-core-mcp:17"
  "apex-commerce-mcp:59"
  "apex-tools-mcp:5"
  "apex-browser-mcp:40"
  "apex-social-mcp:9"
  "apex-data-mcp:8"
  "apex-automation-mcp:16"
)

TIMEOUT_SECS=15
PASS_COUNT=0
FAIL_COUNT=0
TOTAL=${#SERVERS[@]}

# Store results for summary
RESULT_LINES=()

# --- Helper: test one MCP server via Python ----------------------------------
test_server() {
  local name="$1"
  local expected_min="$2"

  python3 << PYEOF
import subprocess, json, sys, time, select, os, signal, shutil

name = "${name}"
expected_min = ${expected_min}
timeout_secs = ${TIMEOUT_SECS}

binary = shutil.which(name)
if not binary:
    print("SKIP|0|binary not found in PATH")
    sys.exit(0)

try:
    proc = subprocess.Popen(
        [binary],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        preexec_fn=os.setsid,
    )
except Exception as e:
    print(f"FAIL|0|failed to start: {e}")
    sys.exit(0)

init_msg = json.dumps({
    "jsonrpc": "2.0", "id": 1, "method": "initialize",
    "params": {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {"name": "smoke-test", "version": "1.0"}
    }
}) + "\n"

tools_msg = json.dumps({
    "jsonrpc": "2.0", "id": 2, "method": "tools/list"
}) + "\n"

try:
    proc.stdin.write(init_msg.encode())
    proc.stdin.write(tools_msg.encode())
    proc.stdin.flush()
    proc.stdin.close()
except Exception as e:
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
    except Exception:
        pass
    print(f"FAIL|0|failed to send messages: {e}")
    sys.exit(0)

responses = []
buf = b""
start = time.time()

try:
    while time.time() - start < timeout_secs:
        ready = select.select([proc.stdout], [], [], 1.0)
        if ready[0]:
            chunk = os.read(proc.stdout.fileno(), 65536)
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                line = line.strip()
                if line:
                    try:
                        responses.append(json.loads(line))
                    except json.JSONDecodeError:
                        pass
            if len(responses) >= 2:
                break
except Exception:
    pass

# Cleanup: kill process group
try:
    os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
except Exception:
    pass
try:
    proc.wait(timeout=3)
except Exception:
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
    except Exception:
        pass

# Evaluate results
if len(responses) < 1:
    print(f"FAIL|0|no response to initialize (timeout {timeout_secs}s)")
    sys.exit(0)

init_resp = responses[0]
if "error" in init_resp:
    msg = init_resp["error"].get("message", "unknown")
    print(f"FAIL|0|initialize error: {msg}")
    sys.exit(0)

if len(responses) < 2:
    print(f"FAIL|0|no response to tools/list (timeout {timeout_secs}s)")
    sys.exit(0)

tools_resp = responses[1]
if "error" in tools_resp:
    msg = tools_resp["error"].get("message", "unknown")
    print(f"FAIL|0|tools/list error: {msg}")
    sys.exit(0)

tools = tools_resp.get("result", {}).get("tools", [])
count = len(tools)

if count >= expected_min:
    print(f"PASS|{count}|")
else:
    print(f"FAIL|{count}|expected >= {expected_min} tools, got {count}")
PYEOF
}

# --- Main --------------------------------------------------------------------
echo ""
echo "=== Apex Radius MCP Suite — Smoke Test ==="
echo "    $(date '+%Y-%m-%d %H:%M:%S')"
echo "    Testing ${TOTAL} servers..."
echo ""

for entry in "${SERVERS[@]}"; do
  server="${entry%%:*}"
  expected="${entry##*:}"

  printf "  %-24s " "$server"

  result=$(test_server "$server" "$expected")
  status=$(echo "$result" | cut -d'|' -f1)
  count=$(echo "$result" | cut -d'|' -f2)
  reason=$(echo "$result" | cut -d'|' -f3-)

  if [ "$status" = "PASS" ]; then
    printf "\033[32mPASS\033[0m (%s tools)\n" "$count"
    PASS_COUNT=$((PASS_COUNT + 1))
    RESULT_LINES+=("PASS|${server}|${count}|")
  elif [ "$status" = "SKIP" ]; then
    printf "\033[33mSKIP\033[0m (%s)\n" "$reason"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    RESULT_LINES+=("SKIP|${server}|${count}|${reason}")
  else
    printf "\033[31mFAIL\033[0m (%s)\n" "$reason"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    RESULT_LINES+=("FAIL|${server}|${count}|${reason}")
  fi
done

# --- Summary -----------------------------------------------------------------
echo ""
echo "==========================================="
echo "=== MCP Suite Smoke Test Results ==="
echo "==========================================="
echo ""

for line in "${RESULT_LINES[@]}"; do
  status=$(echo "$line" | cut -d'|' -f1)
  server=$(echo "$line" | cut -d'|' -f2)
  count=$(echo "$line" | cut -d'|' -f3)
  reason=$(echo "$line" | cut -d'|' -f4-)

  if [ "$status" = "PASS" ]; then
    printf "  %-24s \033[32mPASS\033[0m (%s tools)\n" "$server" "$count"
  elif [ "$status" = "SKIP" ]; then
    printf "  %-24s \033[33mSKIP\033[0m (%s)\n" "$server" "$reason"
  else
    printf "  %-24s \033[31mFAIL\033[0m (%s)\n" "$server" "$reason"
  fi
done

echo ""
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf "  \033[32m=== %d/%d passed ===\033[0m\n" "$PASS_COUNT" "$TOTAL"
else
  printf "  \033[31m=== %d/%d passed, %d failed ===\033[0m\n" "$PASS_COUNT" "$TOTAL" "$FAIL_COUNT"
fi
echo ""

exit "$FAIL_COUNT"
