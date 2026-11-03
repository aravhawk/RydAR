// Lets `node --test` run the TypeScript sources directly. They import siblings as "./x.js"
// (what Vercel's build expects); in a test run that resolves to "./x.ts".
import { existsSync } from "node:fs";
import { registerHooks } from "node:module";
import { fileURLToPath } from "node:url";

registerHooks({
  resolve(specifier, context, next) {
    if (specifier.startsWith(".") && specifier.endsWith(".js") && context.parentURL?.startsWith("file:")) {
      const candidate = new URL(specifier.replace(/\.js$/, ".ts"), context.parentURL);
      const original = new URL(specifier, context.parentURL);
      if (!existsSync(fileURLToPath(original)) && existsSync(fileURLToPath(candidate))) {
        return next(candidate.href, context);
      }
    }
    return next(specifier, context);
  },
});
