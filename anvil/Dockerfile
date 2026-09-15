# Native-platform anvil, built rather than pulled so it never shares an image
# tag with the amd64-pinned forge check.
FROM ghcr.io/foundry-rs/foundry:v1.5.1
HEALTHCHECK --interval=2s --timeout=2s --retries=30 \
  CMD cast block-number --rpc-url http://127.0.0.1:8545 >/dev/null 2>&1 || exit 1
