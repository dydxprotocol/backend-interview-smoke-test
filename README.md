# Backend interview smoke test

A five-minute check that your machine can run the interview project. Run it
the day before; if it passes, the project's `make up` will work first time.

```bash
git clone <this repo> && cd backend-interview-smoke-test
make
```

You should end with `ALL GOOD`. The first run downloads about 2 GB of Docker
images; a second run takes well under a minute. Nothing is left running, and
while it runs the containers listen on `127.0.0.1` only.

Supported: macOS, Linux, and Windows through WSL2. The scripts need `bash`
and `make`, so native Windows without WSL is not supported.

## What you need installed

| Tool | Why | Check |
|---|---|---|
| Docker with Compose v2 | everything in the project runs in containers | `docker compose version` prints `v2.x` |
| `make` | the project is driven by a Makefile | `make --version` |
| `git` | to clone | `git --version` |

Docker Desktop, OrbStack, Rancher Desktop, or Docker Engine plus the compose
plugin all work. That is the whole list: the project itself has no other host
requirements. Whatever language and tooling you use to build your own service
is up to you.

## What `make` verifies

| Step | Checks |
|---|---|
| Host prerequisites | `docker` running, Compose v2, `make`, `git`, free disk, and that ports `8545`, `29092`, `6379`, `8090` are free |
| Images | pulls and builds the same base images the project uses, all pinned to exact versions, so they are cached for interview day |
| Rootchain | a local `anvil` starts natively and mines blocks |
| Solidity toolchain | the amd64 Foundry image compiles and tests a `solc 0.8.35` contract (this runs under emulation on Apple Silicon, and is the step most likely to surprise) |
| Go build | a multi-stage `docker build` with the Go module proxy reachable |
| Kafka | a single-node KRaft broker accepts a single-partition topic and returns three messages in order |
| Redis | answers `PING` |
| From your machine | the published ports answer on `localhost`, the way your service will connect |

## If something fails

- **Docker daemon not reachable**: start Docker Desktop / OrbStack and re-run.
- **Compose v1 or missing**: install the `docker compose` plugin (Docker Desktop includes it; on Linux install `docker-compose-plugin`).
- **Port in use**: copy `.env.example` to `.env` and change the port. The interview project reads the same variables, so you only fix this once.
- **`forge` step fails on `version not found in artifacts for this platform`**: your Docker is not running the amd64 image under emulation. On Apple Silicon, enable Rosetta for x86/amd64 emulation in Docker Desktop settings (OrbStack has it on by default).
- **Slow or failing downloads**: the test reaches these hosts, all over HTTPS. Corporate proxies or VPNs sometimes block one of them; try another network.
  - `ghcr.io` (Foundry image)
  - `docker.io` (Kafka, Redis, Go, and Alpine images)
  - `proxy.golang.org` and `sum.golang.org` (Go modules, during the image build)
  - `binaries.soliditylang.org` (solc 0.8.35, fetched by `forge`)
  - `soldeer-revisions.s3.amazonaws.com` (the `forge-std` library, checksum-pinned in `contracts/soldeer.lock`)

`make check` runs only the host checks. `make up`, `make verify`, and `make down`
run the stages separately if you want to poke at the stack.
