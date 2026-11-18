// Copies the public legal pages (gizlilik, hesap-silme) to build/hosting and
// checks them: no leftover "{{…}}" placeholder, and every internal link points
// at a page that exists (cleanUrls: /gizlilik -> gizlilik.html).
//
//   node hosting/build.mjs
//
// firebase.json runs this as the hosting predeploy step; CI runs it too.
import { cpSync, existsSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const src = join(here, "sayfalar");
const out = join(here, "..", "build", "hosting");

function fail(message) {
  console.error(`hosting/build.mjs: ${message}`);
  process.exit(1);
}

rmSync(out, { recursive: true, force: true });
cpSync(src, out, { recursive: true });

const pages = readdirSync(out).filter((name) => name.endsWith(".html"));
for (const page of pages) {
  const html = readFileSync(join(out, page), "utf8");
  const leftover = html.match(/\{\{[^}]*\}\}/);
  if (leftover) fail(`${page} still has the placeholder ${leftover[0]}.`);
  for (const [, href] of html.matchAll(/href="(\/[^"#?]*)/g)) {
    const target = href === "/" ? "index.html" : href.endsWith(".css") ? href.slice(1) : `${href.slice(1)}.html`;
    if (!existsSync(join(out, target))) fail(`${page} links to ${href}, but ${target} is missing.`);
  }
}

console.log(`hosting/build.mjs: ${pages.length} pages -> build/hosting`);
