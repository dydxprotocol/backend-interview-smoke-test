#!/usr/bin/env bash
# Host prerequisites for the listener interview project. Read-only.
set -u

pass=0; fail=0; warn=0
ok()   { printf "  PASS  %-16s %s\n" "$1" "$2"; pass=$((pass+1)); }
bad()  { printf "  FAIL  %-16s %s\n" "$1" "$2"; fail=$((fail+1)); }
wrn()  { printf "  WARN  %-16s %s\n" "$1" "$2"; warn=$((warn+1)); }
info() { printf "  info  %-16s %s\n" "$1" "$2"; }
have() { command -v "$1" >/dev/null 2>&1; }

# Port overrides, same variables the interview project uses.
[ -f .env ] && set -a && . ./.env && set +a
ANVIL_PORT="${ANVIL_PORT:-8545}"; KAFKA_PORT="${KAFKA_PORT:-29092}"; REDIS_PORT="${REDIS_PORT:-6379}"

echo "Host: $(uname -s) $(uname -m)"

if have git;  then ok "git" "$(git --version | head -1)"; else bad "git" "not found"; fi
if have make; then ok "make" "$(make --version 2>/dev/null | head -1)"; else bad "make" "not found; the project is driven by a Makefile"; fi
if have curl; then ok "curl" "$(curl --version | head -1 | cut -d' ' -f1-2)"; else wrn "curl" "not found (optional; this smoke test uses it for one host check)"; fi

if have docker; then
  if docker info >/dev/null 2>&1; then
    ok "docker daemon" "server $(docker version --format '{{.Server.Version}}' 2>/dev/null), $(docker info --format '{{.OSType}}/{{.Architecture}}' 2>/dev/null)"
  else
    bad "docker daemon" "docker is installed but not running or not reachable; start Docker Desktop / OrbStack / dockerd"
  fi
  if docker compose version >/dev/null 2>&1; then
    v=$(docker compose version --short 2>/dev/null | sed 's/^v//')
    major="${v%%.*}"
    if [ "${major:-0}" -ge 2 ] 2>/dev/null; then
      ok "docker compose" "v$v"
    else
      bad "docker compose" "v$v; the Compose v2+ plugin is required (legacy docker-compose v1 is not enough)"
    fi
  else
    bad "docker compose" "the 'docker compose' plugin is missing (legacy docker-compose v1 is not enough)"
  fi
else
  bad "docker" "not found; install Docker Desktop, OrbStack, or Docker Engine with the compose plugin"
fi

avail=$(df -Pk . 2>/dev/null | awk 'NR==2{printf "%d", $4/1024/1024}')
if [ "${avail:-0}" -ge 5 ]; then ok "free disk" "${avail} GB"; else wrn "free disk" "${avail:-?} GB free; the project's images need about 2 GB"; fi

for spec in "anvil:$ANVIL_PORT" "kafka:$KAFKA_PORT" "redis:$REDIS_PORT" "status:8090"; do
  name="${spec%%:*}"; port="${spec##*:}"
  if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
    wrn "port $port" "in use ($name); the project lets you move it: copy .env.example to .env"
  else
    ok "port $port" "free ($name)"
  fi
done

have go && info "go" "$(go version 2>/dev/null | cut -c1-70)"
for t in node forge cast anvil jq kcat; do
  have "$t" && info "$t" "$("$t" --version 2>/dev/null | head -1 | cut -c1-70)"
done

echo
echo "host checks: $pass passed, $warn warnings, $fail failed"
[ "$fail" -eq 0 ]
