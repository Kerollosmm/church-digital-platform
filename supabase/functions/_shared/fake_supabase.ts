// In-memory fake of the subset of SupabaseClient used by edge functions.
export interface Row { [k: string]: unknown }
export class FakeQuery {
  constructor(
    private db: Map<string, Row[]>,
    private table: string,
    private rows: Row[] | null = null,
    private pendingUpdate: Row | null = null,
  ) {}

  private current(): Row[] {
    const list = this.rows ?? this.db.get(this.table) ?? [];
    if (this.pendingUpdate) {
      for (const r of list) {
        Object.assign(r, this.pendingUpdate);
      }
    }
    return list;
  }

  select() { return this; }
  eq(col: string, val: unknown) {
    const filtered = this.current().filter((r) => r[col] === val);
    return new FakeQuery(this.db, this.table, filtered, this.pendingUpdate);
  }
  order(col: string) {
    const sorted = [...this.current()].sort((a, b) => String(a[col]).localeCompare(String(b[col])));
    return new FakeQuery(this.db, this.table, sorted, this.pendingUpdate);
  }
  limit(n: number) {
    const limited = this.current().slice(0, n);
    return new FakeQuery(this.db, this.table, limited, this.pendingUpdate);
  }
  lt(col: string, val: unknown) {
    const filtered = this.current().filter((r) => r[col] != null && (r[col] as string) < (val as string));
    return new FakeQuery(this.db, this.table, filtered, this.pendingUpdate);
  }
  lte(col: string, val: unknown) {
    const filtered = this.current().filter((r) => r[col] == null || (r[col] as string) <= (val as string));
    return new FakeQuery(this.db, this.table, filtered, this.pendingUpdate);
  }
  gte(col: string, val: unknown) {
    const filtered = this.current().filter((r) => r[col] != null && (r[col] as string) >= (val as string));
    return new FakeQuery(this.db, this.table, filtered, this.pendingUpdate);
  }
  gt(col: string, val: unknown) {
    const filtered = this.current().filter((r) => r[col] != null && (r[col] as string) > (val as string));
    return new FakeQuery(this.db, this.table, filtered, this.pendingUpdate);
  }
  not(col: string, op: string, val: unknown) {
    if (op === "is" && val === null) {
      const filtered = this.current().filter((r) => r[col] != null);
      return new FakeQuery(this.db, this.table, filtered, this.pendingUpdate);
    }
    return this;
  }
  async maybeSingle(): Promise<{ data: Row | null; error: null }> {
    return { data: this.current().at(0) ?? null, error: null };
  }
  async single(): Promise<{ data: Row | null; error: { message: string; code: string } | null }> {
    const r = this.current().at(0);
    if (!r) return { data: null, error: { message: "PGRST116: no row", code: "PGRST116" } };
    return { data: r, error: null };
  }
  insert(row: Row | Row[]) {
    const target = this.db.get(this.table) ?? [];
    if (!this.db.has(this.table)) this.db.set(this.table, target);
    const added: Row[] = [];
    if (Array.isArray(row)) {
      for (const item of row) {
        const full = { id: target.length + 1, ...item };
        target.push(full);
        added.push(full);
      }
    } else {
      const full = { id: target.length + 1, ...row };
      target.push(full);
      added.push(full);
    }
    return new FakeQuery(this.db, this.table, added);
  }
  upsert(row: Row) {
    const rows = this.db.get(this.table) ?? [];
    if (!this.db.has(this.table)) this.db.set(this.table, rows);
    const i = rows.findIndex((r) =>
      (row.id !== undefined && r.id === row.id) ||
      (row.gateway_ref !== undefined && r.gateway_ref === row.gateway_ref) ||
      (row.merchant_order_id !== undefined && r.merchant_order_id === row.merchant_order_id)
    );
    let targetRow: Row;
    if (i >= 0) {
      rows[i] = { ...rows[i], ...row };
      targetRow = rows[i];
    } else {
      targetRow = { id: rows.length + 1, ...row };
      rows.push(targetRow);
    }
    return new FakeQuery(this.db, this.table, [targetRow]);
  }
  update(row: Row) {
    return new FakeQuery(this.db, this.table, this.rows, row);
  }
  then<TResult1 = { data: Row[]; error: null }, TResult2 = never>(
    onfulfilled?: ((value: { data: Row[]; error: null }) => TResult1 | PromiseLike<TResult1>) | null,
    onrejected?: ((reason: any) => TResult2 | PromiseLike<TResult2>) | null
  ): Promise<TResult1 | TResult2> {
    return Promise.resolve({ data: this.current(), error: null }).then(onfulfilled, onrejected);
  }
}
export class FakeClient {
  private db = new Map<string, Row[]>();
  constructor(tables: string[]) { for (const t of tables) this.db.set(t, []); }
  seed(table: string, rows: Row[]) { this.db.set(table, rows); }
  tableRows(table: string): Row[] { return this.db.get(table)!; }
  rpcCalls: string[] = [];
  async rpc(fn: string, args: Record<string, unknown>) {
    this.rpcCalls.push(fn);
    if (fn === "claim_event_outbox_batch") {
      const rows = this.db.get("event_outbox")?.filter((r) => r.status === "PENDING" || r.status === "PROCESSING") ?? [];
      const batchSize = (args?.p_batch_size as number) ?? 100;
      return { data: rows.slice(0, batchSize), error: null };
    }
    return { data: { rpc: fn, args }, error: null };
  }
  from(table: string) { return new FakeQuery(this.db, table); }
}

