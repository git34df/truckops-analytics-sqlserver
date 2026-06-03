
import pandas as pd
from sqlalchemy import create_engine, text
from sqlalchemy.exc import SQLAlchemyError
import urllib
import os

# ─────────────────────────────────────────────
# CONFIGURACIÓN
# ─────────────────────────────────────────────
SERVER   = ""
DATABASE = ""
USE_WINDOWS_AUTH = True
SQL_USER     = ""
SQL_PASSWORD = ""

CSV_FOLDER = r""
CHUNK_SIZE = 1_000


# ─────────────────────────────────────────────
# CONEXIÓN
# ─────────────────────────────────────────────
def get_engine():
    if USE_WINDOWS_AUTH:
        params = urllib.parse.quote_plus(
            f"DRIVER={{ODBC Driver 17 for SQL Server}};"
            f"SERVER={SERVER};"
            f"DATABASE={DATABASE};"
            f"Trusted_Connection=yes;"
            f"TrustServerCertificate=yes;"
        )
    else:
        params = urllib.parse.quote_plus(
            f"DRIVER={{ODBC Driver 17 for SQL Server}};"
            f"SERVER={SERVER};"
            f"DATABASE={DATABASE};"
            f"UID={SQL_USER};"
            f"PWD={SQL_PASSWORD};"
        )
    return create_engine(f"mssql+pyodbc:///?odbc_connect={params}", fast_executemany=True)


# ─────────────────────────────────────────────
# FUNCIONES DE LIMPIEZA
# ─────────────────────────────────────────────
def clean_safety_incidents(df: pd.DataFrame) -> pd.DataFrame:
    df["incident_date"] = pd.to_datetime(df["incident_date"], errors="coerce")
    for col in ["vehicle_damage_cost", "cargo_damage_cost", "claim_amount"]:
        df[col] = pd.to_numeric(df[col], errors="coerce")
    for col in ["at_fault_flag", "injury_flag", "preventable_flag"]:
        df[col] = df[col].map({"True": 1, "False": 0, True: 1, False: 0})
        df[col] = pd.to_numeric(df[col], errors="coerce").astype("Int8")
    return df

def clean_driver_monthly_metrics(df: pd.DataFrame) -> pd.DataFrame:
    df["month"] = pd.to_datetime(df["month"], errors="coerce")
    for col in ["trips_completed", "total_miles", "total_revenue", "average_mpg",
                "total_fuel_gallons", "on_time_delivery_rate", "average_idle_hours"]:
        df[col] = pd.to_numeric(df[col], errors="coerce")
    return df

def clean_truck_utilization_metrics(df: pd.DataFrame) -> pd.DataFrame:
    df["month"] = pd.to_datetime(df["month"], errors="coerce")
    for col in ["trips_completed", "total_miles", "total_revenue", "average_mpg",
                "maintenance_events", "maintenance_cost", "downtime_hours", "utilization_rate"]:
        df[col] = pd.to_numeric(df[col], errors="coerce")
    return df


# ─────────────────────────────────────────────
# ORDEN DE CARGA
# ─────────────────────────────────────────────
LOAD_ORDER = [
    ("safety_incidents",          "safety_incidents.csv",          clean_safety_incidents),
    ("driver_monthly_metrics",    "driver_monthly_metrics.csv",    clean_driver_monthly_metrics),
    ("truck_utilization_metrics", "truck_utilization_metrics.csv", clean_truck_utilization_metrics),
]

# FK obligatorias — filas con NULL aquí se eliminan (no hay valor válido que imputar)
FK_COLS = {
    "safety_incidents":          ["trip_id", "truck_id", "driver_id"],
    "driver_monthly_metrics":    ["driver_id"],
    "truck_utilization_metrics": ["truck_id"],
}

# Numéricos a imputar con mediana
NUMERIC_IMPUTE_COLS = {
    "safety_incidents":          ["vehicle_damage_cost", "cargo_damage_cost", "claim_amount"],
    "driver_monthly_metrics":    ["trips_completed", "total_miles", "total_revenue",
                                  "average_mpg", "total_fuel_gallons",
                                  "on_time_delivery_rate", "average_idle_hours"],
    "truck_utilization_metrics": ["trips_completed", "total_miles", "total_revenue",
                                  "average_mpg", "maintenance_events", "maintenance_cost",
                                  "downtime_hours", "utilization_rate"],
}

# Textos opcionales a imputar con "Unknown"
TEXT_IMPUTE_COLS = {
    "safety_incidents": ["location_city", "location_state", "description", "incident_type"],
}

COMPOSITE_PKS = {
    "driver_monthly_metrics":    ["driver_id", "month"],
    "truck_utilization_metrics": ["truck_id",  "month"],
}


# ─────────────────────────────────────────────
# IMPUTACIÓN DE NULOS
# ─────────────────────────────────────────────
def impute_nulls(df: pd.DataFrame, table_name: str) -> pd.DataFrame:
    original_len = len(df)

    # 1. Eliminar filas con FK nulas
    fk_cols = [c for c in FK_COLS.get(table_name, []) if c in df.columns]
    if fk_cols:
        df = df.dropna(subset=fk_cols)
        dropped = original_len - len(df)
        if dropped:
            print(f"  ⚠️  {dropped} filas eliminadas (FK nula en {fk_cols})")

    # 2. Imputar numéricos con mediana
    for col in [c for c in NUMERIC_IMPUTE_COLS.get(table_name, []) if c in df.columns]:
        n_null = df[col].isna().sum()
        if n_null:
            median_val = df[col].median()
            df[col] = df[col].fillna(median_val)
            print(f"  🔧 '{col}': {n_null} nulos → mediana ({median_val:.4g})")

    # 3. Imputar textos con "Unknown"
    for col in [c for c in TEXT_IMPUTE_COLS.get(table_name, []) if c in df.columns]:
        n_null = df[col].isna().sum()
        if n_null:
            df[col] = df[col].fillna("Unknown")
            print(f"  🔧 '{col}': {n_null} nulos → 'Unknown'")

    return df


# ─────────────────────────────────────────────
# VACIAR TABLAS
# ─────────────────────────────────────────────
def truncate_in_order(engine, table_names: list):
    reversed_tables = list(reversed(table_names))
    with engine.connect() as conn:
        for table in reversed_tables:
            exists = conn.execute(text(
                "SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = :t"
            ), {"t": table}).fetchone()
            if exists:
                conn.execute(text(f"DELETE FROM [{table}]"))
                print(f"  🗑️  Vaciada: [{table}]")
        conn.commit()
    print("  ✅ Tablas vaciadas\n")


# ─────────────────────────────────────────────
# CARGA DE UNA TABLA
# ─────────────────────────────────────────────
def load_table(engine, table_name: str, csv_path: str, clean_fn) -> None:
    print(f"\n{'─'*55}")
    print(f"  Cargando: {table_name}")
    print(f"  Archivo : {csv_path}")

    if not os.path.exists(csv_path):
        print(f"  ⚠️  ARCHIVO NO ENCONTRADO — saltando.")
        return

    df = pd.read_csv(csv_path, low_memory=False)
    print(f"  Filas leídas   : {len(df):,}")

    df = clean_fn(df)

    # Eliminar duplicados en PK
    pk_cols = COMPOSITE_PKS.get(table_name, [df.columns[0]])
    existing_pk_cols = [c for c in pk_cols if c in df.columns]
    dupes = df.duplicated(subset=existing_pk_cols).sum()
    if dupes > 0:
        print(f"  ⚠️  {dupes} duplicados en {existing_pk_cols} — se eliminan.")
        df = df.drop_duplicates(subset=existing_pk_cols)
        
    # Imputar / eliminar nulos
    df = impute_nulls(df, table_name)

    try:
        with engine.connect() as conn:
            exists = conn.execute(text(
                "SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = :t"
            ), {"t": table_name}).fetchone()
            if exists:
                conn.execute(text(f"ALTER TABLE [{table_name}] NOCHECK CONSTRAINT ALL"))
            conn.commit()

        if_exists_mode = "append" if exists else "replace"
        df.to_sql(
            name=table_name,
            con=engine,
            if_exists=if_exists_mode,
            index=False,
            chunksize=CHUNK_SIZE,
        )

        with engine.connect() as conn:
            conn.execute(text(f"ALTER TABLE [{table_name}] CHECK CONSTRAINT ALL"))
            conn.commit()

        print(f"  ✅ Cargadas    : {len(df):,} filas → [{table_name}]")

    except SQLAlchemyError as e:
        print(f"  ❌ ERROR en {table_name}: {e}")


# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────
def main():
    print("=" * 55)
    print("  TruckOps — Carga (tablas pendientes)")
    print(f"  Servidor  : {SERVER}")
    print(f"  Base datos: {DATABASE}")
    print("=" * 55)

    engine = get_engine()

    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        print("Conexión OK")
    except SQLAlchemyError as e:
        print(f"  ❌ No se pudo conectar: {e}")
        return

    table_names = [t[0] for t in LOAD_ORDER]
    print("\n  Vaciando tablas existentes...")
    truncate_in_order(engine, table_names)

    for table_name, csv_file, clean_fn in LOAD_ORDER:
        csv_path = os.path.join(CSV_FOLDER, csv_file)
        load_table(engine, table_name, csv_path, clean_fn)

    print("\n" + "=" * 55)
    print("  Carga finalizada.")
    print("=" * 55)


if __name__ == "__main__":
    main()
