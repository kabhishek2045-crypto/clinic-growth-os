import { describe, expect, it } from 'vitest';
import { compile, sql } from '@/lib/db/sql';

/**
 * The seam is a security control, so these test what it REFUSES as much as what
 * it produces. The specific attack it exists to prevent is a caller reaching the
 * statement text at all — because one `SET LOCAL app.is_platform_admin = 'true'`
 * reads every patient record on the platform (§9.1).
 */

describe('interpolations become parameters, never statement text', () => {
  it('binds a plain value', () => {
    const q = compile(sql`SELECT id FROM app.patients WHERE phone = ${'+919000000001'}`);
    expect(q.text).toBe('SELECT id FROM app.patients WHERE phone = $1');
    expect(q.values).toEqual(['+919000000001']);
  });

  it('binds a classic injection payload as data', () => {
    const payload = "'; DROP TABLE app.patients; --";
    const q = compile(sql`SELECT id FROM app.patients WHERE full_name = ${payload}`);
    expect(q.text).toBe('SELECT id FROM app.patients WHERE full_name = $1');
    expect(q.text).not.toContain('DROP');
    expect(q.values).toEqual([payload]);
  });

  it('binds the elevation payload as data — the attack §9.1 names', () => {
    const payload = "x'; SET LOCAL app.is_platform_admin = 'true'; --";
    const q = compile(sql`SELECT id FROM app.patients WHERE phone = ${payload}`);
    expect(q.text).not.toContain('is_platform_admin');
    expect(q.text).toBe('SELECT id FROM app.patients WHERE phone = $1');
    expect(q.values).toEqual([payload]);
  });

  it('binds null, undefined and objects without stringifying them into the text', () => {
    const q = compile(sql`SELECT ${null}, ${undefined}, ${{ a: 1 }}`);
    expect(q.text).toBe('SELECT $1, $2, $3');
    expect(q.values).toEqual([null, undefined, { a: 1 }]);
  });

  it('numbers parameters in source order', () => {
    const q = compile(sql`SELECT ${'a'}, ${'b'}, ${'c'}`);
    expect(q.text).toBe('SELECT $1, $2, $3');
    expect(q.values).toEqual(['a', 'b', 'c']);
  });
});

describe('composition', () => {
  it('splices a nested fragment and renumbers across the boundary', () => {
    const where = sql`WHERE organization_id = ${'org-1'} AND status = ${'active'}`;
    const q = compile(sql`SELECT ${'col'} FROM app.patients ${where} LIMIT ${10}`);
    expect(q.text).toBe(
      'SELECT $1 FROM app.patients WHERE organization_id = $2 AND status = $3 LIMIT $4',
    );
    expect(q.values).toEqual(['col', 'org-1', 'active', 10]);
  });

  it('joins fragments without parameter collision', () => {
    const ids = ['a', 'b', 'c'].map((v) => sql`${v}`);
    const q = compile(sql`SELECT id FROM app.patients WHERE id IN (${sql.join(ids)})`);
    expect(q.text).toBe('SELECT id FROM app.patients WHERE id IN ($1, $2, $3)');
    expect(q.values).toEqual(['a', 'b', 'c']);
  });

  it('an empty fragment needs no special case at the call site', () => {
    const include = false;
    const maybe = include ? sql`AND deleted_at IS NULL` : sql.empty();
    const q = compile(sql`SELECT id FROM app.patients WHERE id = ${'x'} ${maybe}`);
    expect(q.text).toBe('SELECT id FROM app.patients WHERE id = $1 ');
    expect(q.values).toEqual(['x']);
  });

  it('deep nesting stays correctly numbered', () => {
    const inner = sql`b = ${2}`;
    const middle = sql`a = ${1} AND ${inner}`;
    const q = compile(sql`WHERE ${middle} AND c = ${3}`);
    expect(q.text).toBe('WHERE a = $1 AND b = $2 AND c = $3');
    expect(q.values).toEqual([1, 2, 3]);
  });
});

describe('identifiers are the one place a value reaches the text, and they are narrow', () => {
  it('quotes a valid identifier', () => {
    const q = compile(sql`SELECT * FROM app.${sql.id('patients')}`);
    expect(q.text).toBe('SELECT * FROM app."patients"');
    expect(q.values).toEqual([]);
  });

  it.each([
    ['patients; DROP TABLE app.patients'],
    ['patients"'],
    ['Patients'],
    ['1patients'],
    ['pg_class WHERE 1=1'],
    [''],
  ])('refuses %s rather than escaping it', (name) => {
    expect(() => compile(sql`SELECT * FROM app.${sql.id(name)}`)).toThrow(/not a valid identifier/);
  });
});

describe('the seam cannot be bypassed by type', () => {
  it('a plain string is not a SqlQuery', () => {
    // @ts-expect-error a raw string must not satisfy SqlQuery — this is the control.
    const bad: Parameters<typeof compile>[0] = 'SELECT 1';
    expect(typeof bad).toBe('string');
  });
});
