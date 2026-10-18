FROM node:24-alpine

LABEL maintainer="email-mcp-docker"
LABEL description="IMAP Email MCP Server (stdio) + SSE gateway for LLMs"

# dumb-init for proper SIGTERM handling in MCP (stdio)
# ca-certificates so TLS to imap.gmail.com etc. does not fail with "self-signed certificate"
RUN apk add --no-cache dumb-init ca-certificates && update-ca-certificates

ARG MCP_VERSION=latest
ARG BETTER_EMAIL_VERSION=latest

# MCP server from npm (same code as https://github.com/jdickey1/imap-email-mcp/blob/main/index.js)
# + supergateway to expose stdio as SSE/HTTP for LLMs over the network
# + better-email-mcp (https://github.com/n24q02m/better-email-mcp) for accounts
#   where a password is not enough - e.g. Outlook via OAuth device-code
RUN npm install -g imap-email-mcp@${MCP_VERSION} @n24q02m/better-email-mcp@${BETTER_EMAIL_VERSION} supergateway --omit=dev \
  && npm cache clean --force

# SNI fix: imap-simple does not send servername, Gmail then returns an untrusted cert.
# The patch adds servername=IMAP_HOST to tlsOptions in index.js.
COPY patch-servername.mjs /tmp/patch-servername.mjs
RUN node /tmp/patch-servername.mjs && rm /tmp/patch-servername.mjs

# Non-root for security (mail = sensitive data)
RUN addgroup -S mcp && adduser -S mcp -G mcp
USER mcp

ENV NODE_ENV=production \
  IMAP_PORT=993 \
  IMAP_TLS=true \
  SMTP_PORT=465 \
  SMTP_SECURE=true

# Default: STDIO mode (for opencode / Claude Code / Claude Desktop via `docker run -i`)
ENTRYPOINT ["dumb-init", "--", "imap-email-mcp"]
