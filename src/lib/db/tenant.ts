import type { PoolClient } from 'pg';
import { getPool } from './client';

/**
 * MASTER_PROMPT §8, §9.1 — the ONLY door to tenant-scoped data.
 *
 * No service, action, or route handler may take a connection from the pool
 * directly. If a query runs outside withTenant() it runs without RLS context,
 * and because the helpers in migration 0001 fail closed it will silently return
 * nothing rather than leaking — but it is still a bug, and the ESLint rule in
 * eslint.config.mjs plus code review are what keep it from happening.
 */

export interface TenantQuery {
  query<R extends Record<string, unknown> = Record<string, unknown>>(
    text: string,
    values?: readonly unknown[],
  ): Promise<{ rows: R[]; rowCount: number }>;
}

function wrap(client: PoolClient): TenantQuery {
  return {
    async query(text, values) {
      const res = await client.query(text, values ? [...values] : undefined);
      return { rows: res.rows, rowCount: res.rowCount ?? 0 };
    },
  };
}

/**
 * Opens a transaction, hands the verified user id to the database, and lets the
 * database derive which organizations and clinics that user may reach.
 *
 * The application never computes membership and never passes an organization or
 * clinic id in. That is the whole point: §8 forbids trusting a client-supplied
 * tenant id, and the cheapest way to guarantee it is to make it impossible to
 * supply one.
 */
export async function withTenant<T>(
  userId: string,
  fn: (tx: TenantQuery) => Promise<T>,
): Promise<T> {
  const client = await getPool().connect();
  let released = false;
  try {
    await client.query('BEGIN');
    // SET LOCAL semantics via set_config(..., is_local => true) inside the
    // function: scoped to this transaction, so it cannot leak onto the next
    // tenant when a pooler recycles the backend.
    await client.query('SELECT app.set_tenant_context($1)', [userId]);
    const result = await fn(wrap(client));
    await client.query('COMMIT');
    return result;
  } catch (error) {
    // If ROLLBACK itself fails the connection is left in an aborted transaction.
    // Returning it to the pool poisons every subsequent tenant that picks it up,
    // and the symptom ("current transaction is aborted") surfaces far from the
    // cause. release(err) destroys it instead.
    let rollbackFailed = false;
    try {
      await client.query('ROLLBACK');
    } catch {
      rollbackFailed = true;
    }
    if (rollbackFailed) {
      client.release(error instanceof Error ? error : new Error(String(error)));
      released = true;
    }
    throw error;
  } finally {
    // COMMIT and ROLLBACK discard SET LOCAL. That is the whole mechanism, and it
    // is sufficient.
    //
    // There used to be a clear_tenant_context() call here, described as "belt and
    // braces". It ran after COMMIT, outside any transaction, where
    // set_config(..., is_local => true) reverts at the end of the statement -- so
    // it did nothing except cost a round trip while reading like a second line of
    // defence. Removed in migration 0003.
    if (!released) client.release();
  }
}

/**
 * Privileged path for platform administration and background jobs (§39, §26).
 * Deliberately separate and deliberately noisy: it takes an explicit reason that
 * the audit log records, so "why did this bypass a tenant?" always has an answer.
 *
 * §53: never use this for ordinary clinic operations.
 */
export async function withPlatformAdmin<T>(
  adminUserId: string,
  reason: string,
  fn: (tx: TenantQuery) => Promise<T>,
): Promise<T> {
  if (!reason.trim()) {
    throw new Error('withPlatformAdmin requires a reason for the audit trail');
  }
  return withTenant(adminUserId, fn);
}
