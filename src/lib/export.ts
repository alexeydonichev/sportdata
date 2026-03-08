function sanitizeCell(value: string): string {
  let s = String(value ?? "");
  // Prevent CSV/Excel formula injection
  if (/^[=+\-@\t\r]/.test(s)) {
    s = "'" + s;
  }
  return s;
}

export function exportCSV(filename: string, headers: string[], rows: string[][]) {
  const bom = "\uFEFF";
  const headerLine = headers.join(",");
  const dataLines = rows.map((row) =>
    row.map((cell) => {
      const str = sanitizeCell(cell);
      if (str.includes(",") || str.includes('"') || str.includes("\n")) {
        return '"' + str.replace(/"/g, '""') + '"';
      }
      return str;
    }).join(",")
  ).join("\n");

  const blob = new Blob([bom + headerLine + "\n" + dataLines], {
    type: "text/csv;charset=utf-8;",
  });
  downloadBlob(blob, `${filename}.csv`);
}

export function exportExcel(filename: string, headers: string[], rows: string[][]) {
  const xmlHeader = `<?xml version="1.0" encoding="UTF-8"?>
<?mso-application progid="Excel.Sheet"?>
<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"
  xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
<Styles>
  <Style ss:ID="header"><Font ss:Bold="1"/><Interior ss:Color="#F0F0F0" ss:Pattern="Solid"/></Style>
  <Style ss:ID="num"><NumberFormat ss:Format="#,##0"/></Style>
</Styles>
<Worksheet ss:Name="Данные"><Table>`;

  const xmlFooter = `</Table></Worksheet></Workbook>`;

  const headerRow = `<Row>${headers.map((h) => `<Cell ss:StyleID="header"><Data ss:Type="String">${escXml(h)}</Data></Cell>`).join("")}</Row>`;

  const dataRows = rows.map((row) =>
    `<Row>${row.map((cell) => {
      const safe = sanitizeCell(cell);
      const num = Number(safe);
      if (safe !== "" && !isNaN(num) && isFinite(num)) {
        return `<Cell ss:StyleID="num"><Data ss:Type="Number">${num}</Data></Cell>`;
      }
      return `<Cell><Data ss:Type="String">${escXml(safe)}</Data></Cell>`;
    }).join("")}</Row>`
  ).join("\n");

  const xml = xmlHeader + "\n" + headerRow + "\n" + dataRows + "\n" + xmlFooter;
  const blob = new Blob([xml], { type: "application/vnd.ms-excel;charset=utf-8;" });
  downloadBlob(blob, `${filename}.xls`);
}

function escXml(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function downloadBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
