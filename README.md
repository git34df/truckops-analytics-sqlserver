# TruckOps Analytics — SQL Server

Análisis de operaciones de carga freight en EE.UU.:
modelado relacional en SQL Server con 14 tablas,
ETL con Python y 20 consultas analíticas sobre
revenue, eficiencia de flota, seguridad y comportamiento de clientes.

---

## Stack

![SQL Server](https://img.shields.io/badge/SQL_Server-2019-CC2927?style=flat&logo=microsoftsqlserver&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.x-3776AB?style=flat&logo=python&logoColor=white)
![Pandas](https://img.shields.io/badge/Pandas-ETL-150458?style=flat&logo=pandas&logoColor=white)

---

## Objetivo

Construir un sistema analítico para una operadora de carga
freight que permita responder preguntas de negocio sobre
rentabilidad por ruta, eficiencia de conductores, costos
operativos de flota y seguridad vial, usando SQL Server
como motor principal de análisis.

---

## Arquitectura
Python (ETL) → SQL Server (14 tablas) → Consultas analíticas

## Modelo de datos

| Tabla | Descripción |
|---|---|
| `loads` | Cargas transportadas con revenue y fechas |
| `trips` | Viajes realizados por conductor y camión |
| `drivers` | Conductores activos e históricos |
| `trucks` | Flota de camiones |
| `routes` | Rutas con origen, destino y tarifa base |
| `customers` | Clientes de la operadora |
| `facilities` | Instalaciones de carga y descarga |
| `delivery_events` | Eventos de entrega con OTD flag |
| `fuel_purchases` | Compras de combustible por viaje |
| `maintenance_records` | Historial de mantenimiento por camión |
| `safety_incidents` | Incidentes de seguridad por viaje |
| `driver_monthly_metrics` | Métricas mensuales agregadas por conductor |

---

## Contenido

| Carpeta | Archivo | Descripción |
|---|---|---|
| `src/` | `etl_load.py` | Carga de datos hacia SQL Server |
| `sql/` | `analytical_queries.sql` | 20 consultas analíticas |

---

## Consultas analíticas (20)

Organizadas en cinco bloques temáticos:

### Revenue & Rutas
Ranking de clientes por revenue total, top 10 rutas
por revenue acumulado, evolución mensual con variación
MoM, revenue acumulado como running total y reporte
pivoteado mensual por tipo de carga.

### Eficiencia de Conductores
MPG promedio y horas de ralentí por conductor,
margen bruto estimado (revenue − costo combustible),
ranking dentro de terminal con funciones de ventana,
análisis de cohortes por trimestre de contratación
y alerta de rendimiento cuando el MPG mensual cae
más de 15% respecto al promedio histórico del conductor.

### Costos Operativos de Flota
Costo de mantenimiento total y downtime por camión,
costo de combustible por milla, ranking de los 10
camiones con mayor costo operativo total por milla
(mantenimiento + combustible) y detección de brechas
de disponibilidad por períodos consecutivos de mantenimiento.

### Rentabilidad de Rutas
Revenue efectivo por milla versus tarifa base de cada
ruta. Identifica rutas donde el revenue real está
por debajo del rate mínimo acordado.

### Seguridad Vial
Tasa de incidentes por cada 100 viajes por conductor,
porcentaje de incidentes prevenibles por nivel de
experiencia (Novatos / Intermedios / Expertos / Veteranos)
y comparativa versus la media general de la flota.

### Comportamiento de Clientes
Porcentaje de entregas a tiempo (OTD) por cliente
y segmentación RFM (Recency, Frequency, Monetary)
con clasificación High / Mid / Low usando NTILE.

→ Ver todas las consultas en `sql/analytical_queries.sql`

---

## Técnicas SQL utilizadas

| Técnica | Uso |
|---|---|
| CTEs encadenadas | Consultas de costos operativos y RFM |
| Window Functions | `RANK()`, `LAG()`, `SUM() OVER()`, `NTILE()` |
| PIVOT | Reporte mensual por tipo de carga |
| CROSS JOIN | Comparativa vs media general de flota |
| DATEDIFF + LAG | Detección de brechas de mantenimiento |
| CASE WHEN | Segmentación por experiencia y RFM |

---

## Cómo ejecutar

```bash
# 1. Instalar dependencias
pip install pandas sqlalchemy pyodbc

# 2. Configurar servidor en config.py
cp config.example.py config.py

# 3. Ejecutar ETL
python src/etl_load.py

# 4. Correr consultas analíticas
# Abrir sql/analytical_queries.sql en SSMS y ejecutar
```

> Requiere SQL Server con Windows Authentication
> y ODBC Driver 17 for SQL Server instalado.

---

## Autor

**Diego Torres Andrade**
Estudiante de Ingeniería de Sistemas — UPN Lima
Orientado a Data Analytics & Business Intelligence

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Conectar-0A66C2?style=flat&logo=linkedin)](https://linkedin.com/in/tu-usuario)
[![Portfolio](https://img.shields.io/badge/Portfolio-Ver_más-1a1a2e?style=flat)](https://tu-portfolio.vercel.app)



