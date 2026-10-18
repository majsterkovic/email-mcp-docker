# AGENTS.md — Email MCP: instructions for LLM agents

Goal: search, read and (carefully) manage the user's mail through MCP.
This project builds the `imap-email-mcp:local` Docker image (Node 24), which contains TWO MCP servers — one per mailbox:

| Mailbox | Server (binary in the image) | Auth |
|---|---|---|
| Gmail / any IMAP provider | `imap-email-mcp` | app password in `.env.gmail` |
| Outlook / Microsoft 365 | `better-email-mcp` | OAuth2, token in `./better-email-data/tokens.json` |

Why two servers: Microsoft disabled password login on IMAP
(`Logging in is disabled on this server`), so Outlook requires OAuth (device-code).
Gmail works with an app password.

## 1. Architecture (what lives where)

One Docker image, two MCP servers:

- `imap-email-mcp` (npm) — the Gmail/generic-IMAP server, plus an SSE bridge via `supergateway` (`imap-mcp-sse` service).
- `better-email-mcp` (npm) — the Outlook server using OAuth device-code tokens.

Secrets: `.env.gmail` (Gmail app password), `.env.outlook` (placeholder only), `./better-email-data/tokens.json` (Outlook OAuth). Never log or commit them.

## 2. How to connect

### Option A — SSE (single account, server already running)
- Container `imap-mcp-sse`: `docker compose up -d imap-mcp-sse`
- Endpoint: `http://localhost:3000/sse` (127.0.0.1 only, healthcheck in compose)
- opencode: `"imap-gmail-sse": {"type": "remote", "url": "http://localhost:3000/sse"}`

### Option B — STDIO (both accounts, no daemons)
Gmail:
```
docker run -i --rm --env-file /path/to/email-mcp-docker/.env.gmail imap-email-mcp:local
```
Outlook (needs mounted tokens + ANY placeholder password — the OAuth token authorizes):
```
docker run -i --rm --user 1000:1000 --entrypoint better-email-mcp \
  -v /path/to/email-mcp-docker/better-email-data:/home/node/.better-email-mcp \
  -e EMAIL_CREDENTIALS="you@outlook.com:oauth-token-in-store" \
  imap-email-mcp:local
```
Ready-to-paste entries for `opencode.json`: see `opencode.example.json`
(`imap-gmail-stdio`, `imap-outlook-better-email`).

## 3. Gmail — tools (`imap-email-mcp`)

- `list_folders` — returns folders. Typical: `INBOX`, `[Gmail]/...` (All Mail, Spam, Trash…),
  plus any custom labels/folders.
- `list_emails` — args: `folder` (default `INBOX`), `limit` (default 20),
  `unseen_only` (bool), `since_date` (`YYYY-MM-DD`). Returns uid/date/from/to/subject/flags (no body).
- `get_email` — `uid` (REQUIRED), `folder`. Returns the full `text` (+ `html`).
- `search_emails` — `folder`, `subject`, `from`, `body`, `limit`. Substring filters; combine them for precision.
- `list_drafts` / `get_draft(uid)` / `create_draft(to, subject, body?, html?, cc?, bcc?)`
  / `update_draft(uid, to, subject, ...)` / `send_email(to, subject, ...)` / `delete_email(uid, folder)`.

Search flow: run `search_emails`/`list_emails` first (small `limit`), then `get_email` on the chosen uids.
UIDs are unique WITHIN a folder — when you switch folders, fetch a fresh list.

## 4. Outlook — tools (`better-email-mcp`)

The server derives an `account_id` from the configured email (e.g. `you_example_com`).
Folders: `INBOX`, `Sent`, `Drafts`, `Archive`, `Junk`, `Deleted`, …

- `messages` — one mega-tool, `action` parameter:
  - `search` — args: `query` (IMAP language, see below), `folder` (default INBOX), `limit`.
    Returns `total`, `messages[]` (uid/message_id/subject/from/to/date/snippet).
  - `read` — full content (by uid or message_id).
  - `mark_read` / `mark_unread` / `flag` / `unflag` / `move` / `archive` / `trash`.
  - `new` / `reply` / `forward` — compose/send (see section 6).
- `folders` — `action: list` (folder list) / `status` (counters).
- `attachments` — `list` / `download`.
- `help` — full tool documentation; `config` — configuration status.

`query` syntax (IMAP, case-insensitive, conditions are AND-ed):
`UNREAD`, `FLAGGED`, `SINCE 2026-08-01`, `FROM boss@company.com`, `SUBJECT invoice`,
e.g. `UNREAD SINCE 2026-09-01`, `FROM newsletter.com SUBJECT promo`.

## 5. Common tasks (patterns)

- "Unread from last week": Gmail `list_emails {unseen_only:true, since_date:"<date>", limit:20}`;
  Outlook `messages {action:search, query:"UNREAD SINCE <YYYY-MM-DD>"}`.
- "Invoices from August": `search_emails {subject:"invoice"}` + `body:"invoice"`; Outlook: `SUBJECT invoice`.
- "Mail from X about Y": `search_emails {from:"X", subject:"Y"}` / `FROM X SUBJECT Y`.
- "Show full content": take `uid` from results and call `get_email` / `messages read`.

Always show the user: date, sender, subject and a 1-2 sentence summary; full content only on request.
Do not dump raw HTML or secrets (tokens, passwords, unsubscribe links) unless needed.

## 6. Safety rules (MANDATORY)

1. You are READ-ONLY by default: `search` / `list` / `read` / `get_email`.
2. `send_email` / `messages new,reply,forward` — ONLY on explicit request; show a draft first
   (`create_draft`) and wait for approval of the content + recipients.
3. `delete_email` / `trash` / `move` — ONLY on explicit request; confirm uid and subject.
4. Never display or log: passwords, tokens (`tokens.json`), full auth headers.
5. Never commit: `.env*`, `better-email-data/` (protected by `.gitignore`).
6. The Outlook token refreshes itself; if a search returns an auth error — report it to the human
   (re-run `docker compose --profile outlook up better-email-auth`), do not try the password.

## 7. Maintenance (when something breaks)

```bash
docker compose ps                                  # status
docker compose logs --tail=30 imap-mcp-sse         # Gmail SSE logs
docker compose up -d imap-mcp-sse                  # restart Gmail SSE
docker compose --profile outlook up better-email-auth   # re-do Outlook OAuth
docker compose build                               # rebuild (Dockerfile SNI patch)
```

Known pitfalls:
- `self-signed certificate` (Gmail) — fixed by the bundled `patch-servername.mjs` patch
  (SNI in `tlsOptions`); after `npm update imap-email-mcp` check the patch still applies (`PATCH OK` in the build).
- Outlook `Logging in is disabled` — expected for password login; use ONLY `better-email-mcp`.
- better-email without `EMAIL_CREDENTIALS` refuses to start in stdio (`Missing required env vars`) —
  the placeholder password is required but ignored (the token is what counts).
- Ports: 3000 = Gmail SSE. Outlook has no SSE daemon (stdio + token file).
