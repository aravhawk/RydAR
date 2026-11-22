import { readFileSync } from "node:fs";
import { serve } from "@hono/node-server";
import { serveStatic } from "@hono/node-server/serve-static";
import { Hono } from "hono";
import api from "./server.js";

const app = new Hono();
const publicRoot = "./public";
const notFoundPage = readFileSync(`${publicRoot}/404.html`, "utf8");
const { routes } = JSON.parse(readFileSync("vercel.json", "utf8"));
const canonicalPage = new RegExp(routes.find((route: { dest?: string }) => route.dest === "/$1.html").src);

app.use("/api/*", async (context, next) => {
  await next();
  context.header("X-Robots-Tag", "noindex");
});
app.route("/", api);

app.get("*", (context, next) => {
  const path = context.req.path;
  if (/^\/index(?:\.html)?\/?$/.test(path)) {
    return context.redirect("/" + new URL(context.req.url).search, 308);
  }

  const canonicalPath = path.replace(/(?:\.html)?\/$|\.html$/, "");
  if (canonicalPath !== path && canonicalPage.test(canonicalPath)) {
    return context.redirect(canonicalPath + new URL(context.req.url).search, 308);
  }

  return next();
});
app.get("*", serveStatic({
  root: publicRoot,
  rewriteRequestPath: (path) => canonicalPage.test(path) ? `${path}.html` : path,
}));
app.notFound((context) => context.html(notFoundPage, 404));

serve({
  fetch: app.fetch,
  hostname: "0.0.0.0",
  port: Number(process.env.PORT ?? 3000),
});
