import { handle } from "hono/vercel";
import app from "../server.js";

const fetchApp = handle(app);

export function POST(request: Request) {
  return fetchApp(request);
}
