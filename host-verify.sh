#!/usr/bin/env bash
# Reachability of the running stack from THIS machine, the way your listener
# will connect to it: published ports on localhost.
set -u
[ -f .env ] && set -a && . ./.env && set +a
ANVIL_PORT="${ANVIL_PORT:-8545}"; KAFKA_PORT="${KAFKA_PORT:-29092}"; REDIS_PORT="${REDIS_PORT:-6379}"
fail=0
ok()  { printf "  PASS  %-16s %s\n" "$1" "$2"; }
bad() { printf "  FAIL  %-16s %s\n" "$1" "$2"; fail=$((fail+1)); }

if command -v curl >/dev/null 2>&1; then
  chain=$(curl -sS -m 5 -X POST "http://127.0.0.1:$ANVIL_PORT" -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' 2>/dev/null | sed -n 's/.*"result":"\(0x[0-9a-f]*\)".*/\1/p')
  if [ "$chain" = "0x7a69" ]; then ok "rpc :$ANVIL_PORT" "eth_chainId = 31337"; else bad "rpc :$ANVIL_PORT" "no JSON-RPC answer (got '${chain:-nothing}')"; fi
else
  if (exec 3<>"/dev/tcp/127.0.0.1/$ANVIL_PORT") 2>/dev/null; then ok "rpc :$ANVIL_PORT" "tcp reachable (curl not installed; skipped JSON-RPC call)"; else bad "rpc :$ANVIL_PORT" "not reachable"; fi
fi

if reply=$( (exec 3<>"/dev/tcp/127.0.0.1/$REDIS_PORT" && printf '*1\r\n$4\r\nPING\r\n' >&3 && head -c 7 <&3) 2>/dev/null ) && [ "${reply%%$'\r'*}" = "+PONG" ]; then
  ok "redis :$REDIS_PORT" "PING -> PONG"
else
  bad "redis :$REDIS_PORT" "no PONG"
fi

if (exec 3<>"/dev/tcp/127.0.0.1/$KAFKA_PORT") 2>/dev/null; then
  ok "kafka :$KAFKA_PORT" "tcp reachable (broker advertises localhost:$KAFKA_PORT to host clients)"
else
  bad "kafka :$KAFKA_PORT" "not reachable"
fi

[ "$fail" -eq 0 ] || { echo "host reachability: $fail failed"; exit 1; }
echo "host reachability: all passed"
