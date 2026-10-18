# email-mcp-docker

> For LLM agents: the full mailbox-operations guide is in **`AGENTS.md`** — hand it to your local agent together with the task.

Local MCP servers with mailbox access over IMAP/SMTP, packaged as a Docker image.
Built on top of [`jdickey1/imap-email-mcp`](https://github.com/jdickey1/imap-email-mcp) (installed from npm as `imap-email-mcp`), so an LLM can use it locally.

The image ships two servers:

| Mailbox | Server (binary in the image) | Auth |
|---|---|---|
| Gmail / any IMAP provider | `imap-email-mcp` | app password in `.env.gmail` |
| Outlook / Microsoft 365 | `better-email-mcp` | OAuth2 device-code (Microsoft disabled password login on IMAP) |

Two connection modes (per mailbox):

1. **STDIO** - for opencode / Claude Code / Claude Desktop / Cursor. The LLM spawns `docker run -i ...`.
2. **SSE** - a local server (`http://localhost:3000/sse`). The LLM connects over the network. Good when the MCP client cannot spawn local commands.

## 1. Setup - Gmail

```bash
cp .env.gmail.example .env.gmail
# edit .env.gmail - set IMAP_USER / IMAP_PASSWORD (app password!) / IMAP_HOST
docker compose build
```

Gmail: generate an App Password: https://myaccount.google.com/apppasswords

## 2. Second mailbox - Outlook (OAuth device-code)

A password will NOT work here — Microsoft disabled password login on IMAP.
We use `better-email-mcp` (bundled in this image) with a one-off browser login:

```bash
docker compose --profile outlook up better-email-auth
# prints a https://www.microsoft.com/link URL + code -> sign in to Microsoft
# the token is stored in ./better-email-data/tokens.json (never commit!)
```

MCP server (stdio) for the LLM, on the saved token:
```bash
docker run -i --rm --user 1000:1000 --entrypoint better-email-mcp \
  -v ./better-email-data:/home/node/.better-email-mcp \
  -e EMAIL_CREDENTIALS="you@outlook.com:oauth-token-in-store" \
  imap-email-mcp:local
```

In opencode (`opencode.example.json`, entry `imap-outlook-better-email`).
Tools: `messages` (search/read/reply/...), `folders`, `attachments`.

## 3. Test STDIO

```bash
docker run -i --rm --env-file .env.gmail imap-email-mcp:local
# then paste: {"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}
# Ctrl-D to exit. If it prints the tool list (list_folders, list_emails...) = it works.
```

## 4. SSE mode (local server for LLMs)

```bash
docker compose up -d imap-mcp-sse
docker compose logs -f imap-mcp-sse
curl -i http://localhost:3000/sse
```

Stop:
```bash
docker compose down
```

## 5. Connecting your LLM

### opencode
Paste into `opencode.json` (see `opencode.example.json`):

STDIO (Gmail):
```json
{
  "mcp": {
    "imap-gmail": {
      "type": "local",
      "command": ["docker", "run", "-i", "--rm", "--env-file", "/path/to/email-mcp-docker/.env.gmail", "imap-email-mcp:local"],
      "enabled": true
    }
  }
}
```

or SSE (requires `docker compose up -d imap-mcp-sse`):
```json
{
  "mcp": {
    "imap-gmail": { "type": "remote", "url": "http://localhost:3000/sse", "enabled": true }
  }
}
```

### Claude Code CLI
```bash
claude mcp add imap-gmail -- docker run -i --rm --env-file /path/to/email-mcp-docker/.env.gmail imap-email-mcp:local
```

### Claude Desktop (`claude_desktop_config.json`)
```json
{
  "mcpServers": {
    "imap-gmail": {
      "command": "docker",
      "args": ["run", "-i", "--rm", "--env-file", "/path/to/email-mcp-docker/.env.gmail", "imap-email-mcp:local"]
    }
  }
}
```

## Technical notes
- The image includes the `patch-servername.mjs` patch: it adds `servername=IMAP_HOST` to `tlsOptions`, because `imap-simple` does not send SNI and Gmail then returns an untrusted cert (`self-signed certificate`).
- The image includes `ca-certificates` and runs as non-root `mcp`.

## Security
- Bound to `127.0.0.1:3000` only; do not expose to the internet without auth.
- Use an App Password, not your main password. Revoke it after testing.
- Never commit `.env*` (kept in `.dockerignore` / `.gitignore`).
