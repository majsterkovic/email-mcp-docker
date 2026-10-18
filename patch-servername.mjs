// Build-time patch for imap-email-mcp (npm).
// Problem: imap-simple / node-imap opens TLS without sending SNI (servername),
// and the Gmail frontend returns a fallback certificate without SNI that Node does not trust
// -> "Error: self-signed certificate" on list_folders / list_emails / ....
// Fix: add servername = IMAP_HOST to tlsOptions in index.js.
import fs from 'node:fs';

const p = '/usr/local/lib/node_modules/imap-email-mcp/index.js';
const src = fs.readFileSync(p, 'utf8');

const needle = 'rejectUnauthorized: process.env.IMAP_TLS_REJECT_UNAUTHORIZED !==';
if (!src.includes(needle)) {
  console.error('PATCH: tlsOptions block not found, upstream may have changed!');
  process.exit(1);
}
if (src.includes('servername: process.env.IMAP_HOST')) {
  console.log('PATCH: servername already present, nothing to do.');
  process.exit(0);
}

const patched = src.replace(
  'rejectUnauthorized: process.env.IMAP_TLS_REJECT_UNAUTHORIZED !== \'false\'',
  'rejectUnauthorized: process.env.IMAP_TLS_REJECT_UNAUTHORIZED !== \'false\',\n      servername: process.env.IMAP_HOST // docker-fix: SNI required by Gmail'
);

if (patched === src) {
  console.error('PATCH: replace did not change anything!');
  process.exit(1);
}
fs.writeFileSync(p, patched);
console.log('PATCH OK: servername added to tlsOptions.');
