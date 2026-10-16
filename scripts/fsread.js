#!/usr/bin/env node
// Read-only Firestore peek using the Firebase CLI's own login (never writes).
//   node scripts/fsread.js doc <path>            e.g. doc monthly/ffl_2026-10
//   node scripts/fsread.js col <collection> [limit]
const FT = process.env.HOME + "/.npm-global/lib/node_modules/firebase-tools";
const cfg = require(process.env.HOME + "/.config/configstore/firebase-tools.json");
require(FT + "/lib/apiv2").setRefreshToken(cfg.tokens.refresh_token);
const fs = require(FT + "/lib/gcp/firestore");
const P = "travelbuddy-12d76";
const val = (v) => {
  if (v == null) return null;
  if ("stringValue" in v) return v.stringValue;
  if ("integerValue" in v) return Number(v.integerValue);
  if ("doubleValue" in v) return v.doubleValue;
  if ("booleanValue" in v) return v.booleanValue;
  if ("timestampValue" in v) return v.timestampValue;
  if ("nullValue" in v) return null;
  if ("mapValue" in v) return Object.fromEntries(Object.entries(v.mapValue.fields || {}).map(([k, x]) => [k, val(x)]));
  if ("arrayValue" in v) return (v.arrayValue.values || []).map(val);
  return v;
};
const fields = (d) => Object.fromEntries(Object.entries(d.fields || {}).map(([k, x]) => [k, val(x)]));
(async () => {
  const [cmd, arg, lim] = process.argv.slice(2);
  if (cmd === "doc") {
    const r = await fs.getDocuments(P, [arg]);
    for (const d of r.documents) console.log(JSON.stringify(fields(d), null, 1));
    for (const m of r.missing) console.log("MISSING", m);
  } else if (cmd === "col") {
    const r = await fs.queryCollection(P, { from: [{ collectionId: arg }], limit: Number(lim || 20) });
    for (const d of r.documents) console.log(d.name.split("/").pop(), JSON.stringify(fields(d)));
  }
})().catch((e) => { console.error("ERR", e.message); process.exit(1); });
