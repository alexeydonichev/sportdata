import pool from "@/lib/db";

export interface GeoData {
  by_country: { country: string; revenue: number; quantity: number; orders: number; returns: number; return_rate: number }[];
  by_warehouse: { warehouse: string; revenue: number; quantity: number; orders: number; returns: number }[];
  by_pvz: { pvz: string; revenue: number; quantity: number }[];
  summary: { countries: number; warehouses: number; total_revenue: number; top_country: string; top_warehouse: string };
}

export async function getGeography(days: number, category?: string, marketplace?: string): Promise<GeoData> {
  const params: (number|string)[] = [days];
  let catF="", mpJ="", mpF="";
  if (category&&category!=="all") { params.push(category); catF=`AND c.slug=$${params.length}`; }
  if (marketplace&&marketplace!=="all") { params.push(marketplace); mpJ="JOIN marketplaces mp ON mp.id=s.marketplace_id"; mpF=`AND mp.slug=$${params.length}`; }

  const countryRes = await pool.query(`
    SELECT COALESCE(s.site_country,'Россия') AS country,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.revenue ELSE 0 END),0)::float AS revenue,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END),0)::int AS quantity,
      COUNT(CASE WHEN s.quantity>0 THEN 1 END)::int AS orders,
      COALESCE(SUM(CASE WHEN s.quantity<0 THEN ABS(s.quantity) ELSE 0 END),0)::int AS returns
    FROM sales s JOIN products p ON p.id=s.product_id LEFT JOIN categories c ON c.id=p.category_id ${mpJ}
    WHERE s.sale_date>=CURRENT_DATE-$1::int ${catF} ${mpF}
    GROUP BY s.site_country ORDER BY revenue DESC
  `, params);

  const byCountry = countryRes.rows.map((r: {country:string;revenue:number;quantity:number;orders:number;returns:number}) => ({
    ...r, return_rate: (r.quantity+r.returns)>0 ? parseFloat(((r.returns/(r.quantity+r.returns))*100).toFixed(1)) : 0,
  }));

  const whRes = await pool.query(`
    SELECT COALESCE(s.office_name,'Не указан') AS warehouse,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.revenue ELSE 0 END),0)::float AS revenue,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END),0)::int AS quantity,
      COUNT(CASE WHEN s.quantity>0 THEN 1 END)::int AS orders,
      COALESCE(SUM(CASE WHEN s.quantity<0 THEN ABS(s.quantity) ELSE 0 END),0)::int AS returns
    FROM sales s JOIN products p ON p.id=s.product_id LEFT JOIN categories c ON c.id=p.category_id ${mpJ}
    WHERE s.sale_date>=CURRENT_DATE-$1::int AND s.office_name IS NOT NULL ${catF} ${mpF}
    GROUP BY s.office_name ORDER BY revenue DESC LIMIT 30
  `, params);

  const pvzRes = await pool.query(`
    SELECT COALESCE(s.ppvz_office_name,'Не указан') AS pvz,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.revenue ELSE 0 END),0)::float AS revenue,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END),0)::int AS quantity
    FROM sales s JOIN products p ON p.id=s.product_id LEFT JOIN categories c ON c.id=p.category_id ${mpJ}
    WHERE s.sale_date>=CURRENT_DATE-$1::int AND s.ppvz_office_name IS NOT NULL ${catF} ${mpF}
    GROUP BY s.ppvz_office_name ORDER BY revenue DESC LIMIT 20
  `, params);

  const totalRev = byCountry.reduce((s: number, r: {revenue:number}) => s + r.revenue, 0);

  return {
    by_country: byCountry,
    by_warehouse: whRes.rows,
    by_pvz: pvzRes.rows,
    summary: {
      countries: byCountry.length,
      warehouses: whRes.rows.length,
      total_revenue: totalRev,
      top_country: byCountry[0]?.country || "-",
      top_warehouse: whRes.rows[0]?.warehouse || "-",
    },
  };
}
