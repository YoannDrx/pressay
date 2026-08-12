import { neon } from "@neondatabase/serverless";

type ClerkEmail = {
  id: string;
  email_address: string;
  verification?: { status?: string } | null;
};

type ClerkUser = {
  id: string;
  primary_email_address_id?: string | null;
  email_addresses: ClerkEmail[];
  first_name?: string | null;
  last_name?: string | null;
  image_url?: string | null;
  created_at: number;
  updated_at: number;
};

type MigrationCandidate = {
  id: string;
  email: string;
  name: string;
  image: string | null;
  createdAt: Date;
  updatedAt: Date;
};

const apply = process.argv.includes("--apply");
const fromAccounts = process.argv.includes("--from-accounts");
const clerkSecret = process.env.CLERK_SECRET_KEY;
const databaseURL = process.env.DATABASE_URL;

if (!fromAccounts && !clerkSecret) throw new Error("CLERK_SECRET_KEY is required unless --from-accounts is used");
if ((fromAccounts || apply) && !databaseURL) {
  throw new Error("DATABASE_URL is required with --from-accounts or --apply");
}

const sql = databaseURL ? neon(databaseURL) : null;
const users = fromAccounts ? [] : await listAllClerkUsers(clerkSecret!);
const candidates: MigrationCandidate[] = fromAccounts
  ? await listAccountCandidates(sql!)
  : users.flatMap((user) => {
      const primary = user.email_addresses.find((email) => email.id === user.primary_email_address_id)
        ?? user.email_addresses[0];
      if (!primary || primary.verification?.status !== "verified") return [];
      const name = [user.first_name, user.last_name].filter(Boolean).join(" ").trim()
        || primary.email_address.split("@")[0]
        || "Pressay user";
      return [{
        id: user.id,
        email: primary.email_address.trim().toLowerCase(),
        name,
        image: user.image_url ?? null,
        createdAt: new Date(user.created_at),
        updatedAt: new Date(user.updated_at)
      }];
    });

if (!apply) {
  console.log(JSON.stringify({
    mode: "dry-run",
    source: fromAccounts ? "accounts" : "clerk",
    ...(fromAccounts ? {} : { clerkUsers: users.length }),
    verifiedCandidates: candidates.length,
    ...(fromAccounts ? {} : { skippedUnverified: users.length - candidates.length }),
    next: "Run the same command with --apply after reviewing these counts. Existing sessions are intentionally not imported."
  }, null, 2));
  process.exit(0);
}

let inserted = 0;
let updated = 0;
let conflicts = 0;

for (const candidate of candidates) {
  const sameEmail = await sql!`
    select id from auth_users
    where lower(email) = ${candidate.email}
    limit 1
  `;
  if (sameEmail[0]?.id && sameEmail[0].id !== candidate.id) {
    conflicts += 1;
    continue;
  }
  const existing = await sql!`select id from auth_users where id = ${candidate.id} limit 1`;
  await sql!`
    insert into auth_users (
      id, name, email, "emailVerified", image, "createdAt", "updatedAt", "twoFactorEnabled"
    ) values (
      ${candidate.id}, ${candidate.name}, ${candidate.email}, true, ${candidate.image},
      ${candidate.createdAt}, ${candidate.updatedAt}, false
    )
    on conflict (id) do update set
      name = excluded.name,
      email = excluded.email,
      "emailVerified" = true,
      image = excluded.image,
      "updatedAt" = excluded."updatedAt"
  `;
  if (existing[0]) updated += 1;
  else inserted += 1;
}

console.log(JSON.stringify({
  mode: "apply",
  source: fromAccounts ? "accounts" : "clerk",
  candidates: candidates.length,
  inserted,
  updated,
  conflicts,
  sessionsImported: 0
}, null, 2));

async function listAccountCandidates(sql: ReturnType<typeof neon>): Promise<MigrationCandidate[]> {
  const rows = await sql`
    select auth_subject, email, display_name, created_at, updated_at
    from accounts
    where deleted_at is null and email is not null and btrim(email) <> ''
    order by created_at, id
  `;
  return rows.map((row) => {
    const email = String(row.email).trim().toLowerCase();
    return {
      id: String(row.auth_subject),
      email,
      name: typeof row.display_name === "string" && row.display_name.trim()
        ? row.display_name.trim()
        : email.split("@")[0] || "Pressay user",
      image: null,
      createdAt: new Date(String(row.created_at)),
      updatedAt: new Date(String(row.updated_at))
    };
  });
}

async function listAllClerkUsers(secret: string): Promise<ClerkUser[]> {
  const users: ClerkUser[] = [];
  for (let offset = 0; ; offset += 100) {
    const response = await fetch(`https://api.clerk.com/v1/users?limit=100&offset=${offset}&order_by=created_at`, {
      headers: { Authorization: `Bearer ${secret}` }
    });
    if (!response.ok) throw new Error(`Clerk user export failed (${response.status})`);
    const page = await response.json() as ClerkUser[];
    users.push(...page);
    if (page.length < 100) return users;
  }
}
