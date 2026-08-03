import { neon, type NeonQueryFunction } from "@neondatabase/serverless";

export type Database = NeonQueryFunction<false, false>;

export function createDatabase(connectionString: string): Database {
  return neon(connectionString);
}
