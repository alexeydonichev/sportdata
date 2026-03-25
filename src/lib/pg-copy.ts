
import pool from "./db";

export async function copySales(rows:any[]) {

  if(!rows.length) return;

  rows = rows.filter(r => r && r.sale_date);

  const colsRes = await pool.query(`
    SELECT column_name
    FROM information_schema.columns
    WHERE table_name='sales'
    ORDER BY ordinal_position
  `);

  const cols = colsRes.rows.map(r=>r.column_name);

  const client = await pool.connect();

  try{

    const copyCols = cols.join(",");
    const query = `COPY sales (${copyCols})
FROM STDIN WITH (FORMAT csv, DELIMITER E'\t', NULL '')`;

    const stream = client.query(require("pg-copy-streams").from(query));

    for(const row of rows){

      const line = cols.map(c=>{
        const v=row[c];
        if(v===null||v===undefined) return "";
        return String(v).replace(/\t/g," ").replace(/\n/g," ");
      }).join("\t")+"\n";

      stream.write(line);
    }

    stream.end();

    await new Promise((res,rej)=>{
      stream.on("finish",res);
      stream.on("error",rej);
    });

  }finally{
    client.release();
  }

}
