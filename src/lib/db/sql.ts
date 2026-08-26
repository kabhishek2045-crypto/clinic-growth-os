/**
 * A tagged template that makes raw SQL strings unrepresentable.
 *
 * MASTER_PROMPT §9.1 documents the honest limit of the tenant bridge: Postgres
 * has no ACL on custom GUCs, so anything able to execute arbitrary SQL can
 * simply `SET LOCAL app.is_platform_admin = 'true'` and read every patient
 * record on the platform. The migration comment names the mitigation as
 * "parameterised queries everywhere, and no raw string interpolation" — but the
 * only interface the data layer exposed was `query(text: string, values?)`,
 * which is exactly the shape that mitigation forbids. The guard was a comment.
 *
 * Now it is the type system. `TenantQuery.query()` accepts only a SqlQuery, and
 * the sole way to build one is this tag. Interpolations become bind parameters;
 * they are never concatenated into the statement.
 *
 *   sql`SELECT * FROM app.patients WHERE phone = ${input}`
 *
 * yields text `SELECT * FROM app.patients WHERE phone = $1` and values [input],
 * whatever `input` contains.
 */

const SQL = Symbol('sql.query');

class Param {
  constructor(readonly value: unknown) {}
}

class Ident {
  constructor(readonly name: string) {}
}

type Chunk = string | Param | Ident;

export interface SqlQuery {
  readonly [SQL]: true;
  readonly chunks: readonly Chunk[];
}

function isSqlQuery(v: unknown): v is SqlQuery {
  return typeof v === 'object' && v !== null && SQL in v;
}

/**
 * Identifiers cannot be bind parameters, so they are the one place a value
 * reaches the statement text. Deliberately narrow: lowercase, digits and
 * underscores only, and always double-quoted. Anything else throws rather than
 * being escaped — a table name arriving from user input is a design error, not
 * an encoding problem.
 */
const IDENT = /^[a-z_][a-z0-9_]*$/;

function renderIdent(name: string): string {
  if (!IDENT.test(name)) {
    throw new Error(
      `sql.id: ${JSON.stringify(name)} is not a valid identifier. ` +
        'Identifiers must match /^[a-z_][a-z0-9_]*$/ and must never come from user input.',
    );
  }
  return `"${name}"`;
}

function build(strings: readonly string[], values: readonly unknown[]): SqlQuery {
  const chunks: Chunk[] = [];
  for (let i = 0; i < strings.length; i += 1) {
    chunks.push(strings[i] ?? '');
    if (i < values.length) {
      const v = values[i];
      if (isSqlQuery(v)) {
        // Composition splices the fragment's chunks inline, so parameter
        // numbering is decided once at compile time and nested fragments cannot
        // collide.
        chunks.push(...v.chunks);
      } else if (v instanceof Ident) {
        chunks.push(v);
      } else {
        chunks.push(new Param(v));
      }
    }
  }
  return { [SQL]: true, chunks };
}

export function sql(strings: TemplateStringsArray, ...values: unknown[]): SqlQuery {
  return build(strings, values);
}

/** A validated, quoted identifier. Never accepts user input. */
sql.id = (name: string): SqlQuery => ({ [SQL]: true, chunks: [new Ident(name)] });

/** Joins fragments with a separator — for IN lists and dynamic column sets. */
sql.join = (parts: readonly SqlQuery[], separator = ', '): SqlQuery => {
  const chunks: Chunk[] = [];
  parts.forEach((p, i) => {
    if (i > 0) chunks.push(separator);
    chunks.push(...p.chunks);
  });
  return { [SQL]: true, chunks };
};

/** An empty fragment, so conditional composition needs no special case. */
sql.empty = (): SqlQuery => ({ [SQL]: true, chunks: [] });

export function compile(query: SqlQuery): { text: string; values: unknown[] } {
  let text = '';
  const values: unknown[] = [];
  for (const chunk of query.chunks) {
    if (typeof chunk === 'string') {
      text += chunk;
    } else if (chunk instanceof Ident) {
      text += renderIdent(chunk.name);
    } else {
      values.push(chunk.value);
      text += `$${values.length}`;
    }
  }
  return { text, values };
}
