// Builds the public legal pages (gizlilik, hesap-silme) into build/hosting.
//
// The only variable is the contact e-mail. It comes from the ILETISIM_EPOSTA
// environment variable or, if that is empty, from hosting/site.json. Every
// "{{ILETISIM_EPOSTA}}" in hosting/sayfalar/* is replaced with it.
//
//   node hosting/build.mjs                       real build, refuses the placeholder
//   node hosting/build.mjs --allow-placeholder   CI check, keeps the placeholder
//
// firebase.json runs the real build as the hosting predeploy step, so a deploy
// without a real address fails instead of publishing "{{ILETISIM_EPOSTA}}".
import { cpSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const src = join(here, "sayfalar");
const out = join(here, "..", "build", "hosting");
const TOKEN = "{{ILETISIM_EPOSTA}}";
const allowPlaceholder = process.argv.includes("--allow-placeholder");

const config = JSON.parse(readFileSync(join(here, "site.json"), "utf8"));
const email = (process.env.ILETISIM_EPOSTA || config.iletisimEposta || "").trim();

function fail(message) {
  console.error(`hosting/build.mjs: ${message}`);
  process.exit(1);
}

if (email === TOKEN || email === "") {
  if (!allowPlaceholder) {
    fail(
      "contact e-mail is still the placeholder. Set ILETISIM_EPOSTA or fill " +
        "iletisimEposta in hosting/site.json (see hosting/README.md).",
    );
  }
} else if (!/^[^\s@<>"'&]+@[^\s@<>"'&]+\.[a-z]{2,}$/i.test(email)) {
  fail(`"${email}" does not look like an e-mail address.`);
}
const value = email === "" ? TOKEN : email;

rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });

const pages = [];
for (const name of readdirSync(src)) {
  const from = join(src, name);
  if (!/\.(html|css|txt)$/.test(name)) {
    cpSync(from, join(out, name), { recursive: true });
    continue;
  }
  const text = readFileSync(from, "utf8").split(TOKEN).join(value);
  const leftover = text.match(/\{\{[A-Z_]+\}\}/);
  if (leftover && !(allowPlaceholder && leftover[0] === TOKEN)) {
    fail(`${name} has an unknown placeholder ${leftover[0]}.`);
  }
  writeFileSync(join(out, name), text);
  if (name.endsWith(".html")) pages.push(name);
}

// Every internal link must point at a page that exists (cleanUrls: /gizlilik -> gizlilik.html).
for (const page of pages) {
  const html = readFileSync(join(out, page), "utf8");
  for (const [, href] of html.matchAll(/href="(\/[^"#?]*)/g)) {
    const target = href === "/" ? "index.html" : href.endsWith(".css") ? href.slice(1) : `${href.slice(1)}.html`;
    if (!readdirSync(out).includes(target)) fail(`${page} links to ${href}, but ${target} is missing.`);
  }
}

console.log(`hosting/build.mjs: ${pages.length} pages -> build/hosting${value === TOKEN ? " (placeholder kept)" : ""}`);
