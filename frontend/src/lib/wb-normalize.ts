export function normalizeWbSale(row:any){

  const saleDate =
    row.date ||
    row.lastChangeDate ||
    row.saleDate ||
    new Date().toISOString();

  return {
    sale_id: row.saleID ?? null,
    sale_date: new Date(saleDate),

    nm_id: row.nmId ?? null,
    barcode: row.barcode ?? null,

    supplier_article: row.supplierArticle ?? null,
    brand: row.brand ?? null,
    subject_name: row.subject ?? null,

    quantity: row.quantity ?? 1,

    retail_price: row.price ?? null,
    discount_price: row.discountPercent ?? null,
    finished_price: row.finishedPrice ?? null,

    revenue: row.finishedPrice ?? null,
    for_pay: row.forPay ?? null,

    commission: row.ppvzForPay ?? null,
    logistics_cost: row.deliveryRub ?? null,

    supplier_oper_name: row.supplierOperName ?? null,

    warehouse_name: row.warehouseName ?? null,
    oblast: row.oblastOkrugName ?? null,
    country: row.countryName ?? null,

    income_id: row.incomeID ?? null,
    odid: row.odid ?? null,
    srid: row.srid ?? null
  };
}
