import { query, querySingle } from "@/lib/db";

export interface RnpRecord {
  id: number;
  marketplace_id: number;
  marketplace: string;  // slug
  marketplace_name: string;
  operation_date: string;
  category: string;
  category_name: string;
  subcategory: string | null;
  description: string | null;
  amount: number;
  document_id: string | null;
  created_at: string;
  updated_at: string;
}

export interface RnpCategory {
  slug: string;
  name: string;
  parent_slug: string | null;
}

export interface RnpSummary {
  category: string;
  category_name: string;
  total: number;
  count: number;
}

export interface RnpTrendItem {
  date: string;
  total: number;
  by_category: Record<string, number>;
}

export interface RnpFilters {
  startDate?: string;
  endDate?: string;
  marketplace?: string;  // slug
  category?: string;
  limit?: number;
  offset?: number;
}

// Category display names
const CATEGORY_NAMES: Record<string, string> = {
  logistics: "Логистика",
  storage: "Хранение",
  commission: "Комиссия",
  advertising: "Реклама",
  fines: "Штрафы",
  other: "Прочее"
};

export const rnpRepo = {
  async getAll(filters: RnpFilters = {}): Promise<{ records: RnpRecord[]; total: number }> {
    const conditions: string[] = [];
    const params: (string | number)[] = [];
    let paramIndex = 1;

    if (filters.marketplace) {
      conditions.push(`m.slug = $${paramIndex++}`);
      params.push(filters.marketplace);
    }

    if (filters.category) {
      conditions.push(`r.category = $${paramIndex++}`);
      params.push(filters.category);
    }

    if (filters.startDate) {
      conditions.push(`r.operation_date >= $${paramIndex++}`);
      params.push(filters.startDate);
    }

    if (filters.endDate) {
      conditions.push(`r.operation_date <= $${paramIndex++}`);
      params.push(filters.endDate);
    }

    const where = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";
    const limit = filters.limit || 50;
    const offset = filters.offset || 0;

    const [records, countResult] = await Promise.all([
      query<RnpRecord>(`
        SELECT 
          r.id,
          r.marketplace_id,
          m.slug as marketplace,
          m.name as marketplace_name,
          r.operation_date::text as operation_date,
          r.category,
          r.subcategory,
          r.description,
          r.amount::numeric as amount,
          r.document_id,
          r.created_at,
          r.updated_at
        FROM rnp r
        JOIN marketplaces m ON r.marketplace_id = m.id
        ${where}
        ORDER BY r.operation_date DESC, r.id DESC
        LIMIT ${limit} OFFSET ${offset}
      `, params),
      querySingle<{ count: number }>(`
        SELECT COUNT(*)::int as count FROM rnp r
        JOIN marketplaces m ON r.marketplace_id = m.id
        ${where}
      `, params)
    ]);

    // Add category names
    const recordsWithNames = records.map(r => ({
      ...r,
      category_name: CATEGORY_NAMES[r.category] || r.category
    }));

    return { records: recordsWithNames, total: countResult?.count || 0 };
  },

  async getById(id: number): Promise<RnpRecord | null> {
    const record = await querySingle<RnpRecord>(`
      SELECT 
        r.id,
        r.marketplace_id,
        m.slug as marketplace,
        m.name as marketplace_name,
        r.operation_date::text as operation_date,
        r.category,
        r.subcategory,
        r.description,
        r.amount::numeric as amount,
        r.document_id,
        r.created_at,
        r.updated_at
      FROM rnp r
      JOIN marketplaces m ON r.marketplace_id = m.id
      WHERE r.id = $1
    `, [id]);

    if (record) {
      return { ...record, category_name: CATEGORY_NAMES[record.category] || record.category };
    }
    return null;
  },

  async create(data: {
    marketplace: string;
    operation_date: string;
    category: string;
    subcategory?: string | null;
    description?: string | null;
    amount: number;
    document_id?: string | null;
  }): Promise<RnpRecord> {
    // Get marketplace_id by slug
    const mp = await querySingle<{ id: number }>(`SELECT id FROM marketplaces WHERE slug = $1`, [data.marketplace]);
    if (!mp) throw new Error(`Marketplace not found: ${data.marketplace}`);

    const result = await querySingle<RnpRecord>(`
      INSERT INTO rnp (marketplace_id, operation_date, category, subcategory, description, amount, document_id)
      VALUES ($1, $2, $3, $4, $5, $6, $7)
      RETURNING id
    `, [mp.id, data.operation_date, data.category, data.subcategory || null, data.description || null, data.amount, data.document_id || null]);

    return this.getById(result!.id) as Promise<RnpRecord>;
  },

  async update(id: number, data: Partial<{
    marketplace: string;
    operation_date: string;
    category: string;
    subcategory: string | null;
    description: string | null;
    amount: number;
    document_id: string | null;
  }>): Promise<RnpRecord | null> {
    const fields: string[] = [];
    const params: (string | number | null)[] = [];
    let paramIndex = 1;

    if (data.marketplace) {
      const mp = await querySingle<{ id: number }>(`SELECT id FROM marketplaces WHERE slug = $1`, [data.marketplace]);
      if (!mp) throw new Error(`Marketplace not found: ${data.marketplace}`);
      fields.push(`marketplace_id = $${paramIndex++}`);
      params.push(mp.id);
    }

    const directFields = ["operation_date", "category", "subcategory", "description", "amount", "document_id"];
    for (const field of directFields) {
      if (field in data) {
        fields.push(`${field} = $${paramIndex++}`);
        params.push(data[field as keyof typeof data] as string | number | null);
      }
    }

    if (fields.length === 0) return this.getById(id);

    fields.push(`updated_at = NOW()`);
    params.push(id);

    await query(`UPDATE rnp SET ${fields.join(", ")} WHERE id = $${paramIndex}`, params);
    return this.getById(id);
  },

  async delete(id: number): Promise<boolean> {
    const result = await querySingle<{ id: number }>(`DELETE FROM rnp WHERE id = $1 RETURNING id`, [id]);
    return result !== null;
  },

  async getCategories(): Promise<RnpCategory[]> {
    // Return predefined categories since rnp_categories table might not exist
    return [
      { slug: "logistics", name: "Логистика", parent_slug: null },
      { slug: "storage", name: "Хранение", parent_slug: null },
      { slug: "commission", name: "Комиссия", parent_slug: null },
      { slug: "advertising", name: "Реклама", parent_slug: null },
      { slug: "fines", name: "Штрафы", parent_slug: null },
      { slug: "other", name: "Прочее", parent_slug: null },
    ];
  },

  async getSummaryByCategory(filters: { startDate?: string; endDate?: string; marketplace?: string } = {}): Promise<RnpSummary[]> {
    const conditions: string[] = [];
    const params: (string | number)[] = [];
    let paramIndex = 1;

    if (filters.marketplace) {
      conditions.push(`m.slug = $${paramIndex++}`);
      params.push(filters.marketplace);
    }

    if (filters.startDate) {
      conditions.push(`r.operation_date >= $${paramIndex++}`);
      params.push(filters.startDate);
    }

    if (filters.endDate) {
      conditions.push(`r.operation_date <= $${paramIndex++}`);
      params.push(filters.endDate);
    }

    const where = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";

    const rows = await query<{ category: string; total: number; count: number }>(`
      SELECT 
        r.category,
        SUM(r.amount)::numeric as total,
        COUNT(*)::int as count
      FROM rnp r
      JOIN marketplaces m ON r.marketplace_id = m.id
      ${where}
      GROUP BY r.category
      ORDER BY total ASC
    `, params);

    return rows.map(r => ({
      ...r,
      category_name: CATEGORY_NAMES[r.category] || r.category
    }));
  },

  async getTrend(filters: { startDate?: string; endDate?: string; marketplace?: string; groupBy?: "day" | "week" | "month" } = {}): Promise<RnpTrendItem[]> {
    const conditions: string[] = [];
    const params: (string | number)[] = [];
    let paramIndex = 1;

    if (filters.marketplace) {
      conditions.push(`m.slug = $${paramIndex++}`);
      params.push(filters.marketplace);
    }

    if (filters.startDate) {
      conditions.push(`r.operation_date >= $${paramIndex++}`);
      params.push(filters.startDate);
    }

    if (filters.endDate) {
      conditions.push(`r.operation_date <= $${paramIndex++}`);
      params.push(filters.endDate);
    }

    const where = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";

    let dateExpr = "r.operation_date";
    if (filters.groupBy === "week") {
      dateExpr = "date_trunc('week', r.operation_date)::date";
    } else if (filters.groupBy === "month") {
      dateExpr = "date_trunc('month', r.operation_date)::date";
    }

    const rows = await query<{ date: string; category: string; total: number }>(`
      SELECT 
        ${dateExpr}::text as date,
        r.category,
        SUM(r.amount)::numeric as total
      FROM rnp r
      JOIN marketplaces m ON r.marketplace_id = m.id
      ${where}
      GROUP BY 1, r.category
      ORDER BY 1
    `, params);

    // Group by date
    const byDate = new Map<string, RnpTrendItem>();
    for (const row of rows) {
      if (!byDate.has(row.date)) {
        byDate.set(row.date, { date: row.date, total: 0, by_category: {} });
      }
      const trend = byDate.get(row.date)!;
      trend.total += Number(row.total);
      trend.by_category[row.category] = Number(row.total);
    }

    return Array.from(byDate.values());
  },

  async getTotalExpenses(filters: { startDate?: string; endDate?: string; marketplace?: string } = {}): Promise<number> {
    const conditions: string[] = [];
    const params: (string | number)[] = [];
    let paramIndex = 1;

    if (filters.marketplace) {
      conditions.push(`m.slug = $${paramIndex++}`);
      params.push(filters.marketplace);
    }

    if (filters.startDate) {
      conditions.push(`r.operation_date >= $${paramIndex++}`);
      params.push(filters.startDate);
    }

    if (filters.endDate) {
      conditions.push(`r.operation_date <= $${paramIndex++}`);
      params.push(filters.endDate);
    }

    const where = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";

    const result = await querySingle<{ total: number }>(`
      SELECT COALESCE(SUM(r.amount), 0)::numeric as total 
      FROM rnp r
      JOIN marketplaces m ON r.marketplace_id = m.id
      ${where}
    `, params);

    return result?.total || 0;
  }
};
