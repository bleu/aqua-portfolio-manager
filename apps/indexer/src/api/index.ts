// Ponder requires an explicit API endpoint file (unlike Envio, which served GraphQL
// automatically) -- see https://ponder.sh/docs/api-reference/ponder/api-endpoints. Minimal on
// purpose: this indexer has two consumers (apps/web's basket-scope-guard check, apps/arbitrageur's
// sync job), both read-only GraphQL, neither needs the REST/OpenAPI/Swagger layer the other
// Ponder deployment on this host (cow-programmatic-orders-api) also exposes.
import { db } from "ponder:api";
import schema from "ponder:schema";
import { Hono } from "hono";
import { client, graphql } from "ponder";

const app = new Hono();

app.use("/sql/*", client({ db, schema }));
app.use("/", graphql({ db, schema }));
app.use("/graphql", graphql({ db, schema }));

app.get("/healthz", (c) => c.json({ status: "ok" }));

export default app;
