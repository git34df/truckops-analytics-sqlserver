/*Calcular el revenue total, total de cargas y revenue promedio por carga, agrupado por cliente. Ordenar de mayor a menor revenue.*/
SELECT c.customer_name  AS nombre,
       Sum(revenue)     AS total_revenue,
       Count(l.load_id) AS total_Cargas,
       Avg(l.revenue)   AS revenue_promedio
FROM   loads AS l
       INNER JOIN customers AS c
               ON l.customer_id = c.customer_id
GROUP  BY c.customer_name
ORDER  BY total_revenue DESC; 

/*Listar las 10 rutas con mayor revenue total acumulado. Incluir origen, destino, distancia típica y cantidad de cargas realizadas.*/
SELECT TOP 10 Concat(r.origin_city, '->', r.destination_city) AS ruta,
              r.typical_distance_miles,
              Count(l.load_id)                                AS
              cargas_realizadas,
              Sum(l.revenue)                                  AS total_revenue
FROM   loads AS l
       INNER JOIN routes AS r
               ON l.route_id = r.route_id
GROUP  BY r.origin_city,
          r.destination_city,
          r.typical_distance_miles
ORDER  BY total_revenue DESC 

/*Calcular el MPG promedio, total de millas y total de horas de ralentí (idle) por conductor. Filtrar solo conductores activos.*/
SELECT Concat(d.first_name, ' ', d.last_name) AS nombre,
       Avg(t.average_mpg)                     AS mpg_promedio,
       Sum(t.actual_distance_miles)           AS total_millas,
       Sum(t.idle_time_hours)                 AS horas_ralentí_total
FROM   trips AS t
       INNER JOIN drivers AS d
               ON t.driver_id = d.driver_id
WHERE  d.employment_status = 'Active'
GROUP  BY d.first_name,
          d.last_name,
          t.average_mpg
ORDER  BY average_mpg ASC 

/*Obtener el porcentaje de entregas a tiempo (on_time_flag) por cliente. Calcular total de eventos, total on-time y el % resultante.*/

SELECT c.customer_name                                         AS cliente,
       Count(de.event_id)                                      AS total_eventos,
       Sum(CASE
             WHEN de.on_time_flag = 1 THEN 1
             ELSE 0
           END)                                                AS total_on_time,
       Round(( Sum(CASE
                     WHEN de.on_time_flag = 1 THEN 1
                     ELSE 0
                   END) * 1.0 / Count(de.event_id) ), 3) * 100 AS
       pct_total_on_time
FROM   delivery_events AS de
       INNER JOIN loads AS l
               ON de.load_id = l.load_id
       INNER JOIN customers AS c
               ON l.customer_id = c.customer_id
GROUP  BY c.customer_name
ORDER  BY pct_total_on_time DESC 

/*Calcular el costo total de mantenimiento por camión (labor + partes), 
junto con el total de horas de downtime y cantidad de intervenciones. Ordenar por costo descendente.*/
SELECT Concat(t.make, '-', t.model_year) AS truck,
       Sum(mr.total_cost)                AS cost_maintenance,
       Sum(mr.downtime_hours)            AS hours_maintenance,
       Count(mr.maintenance_id)          AS cant_intervenciones
FROM   maintenance_records AS mr
       INNER JOIN trucks AS t
               ON mr.truck_id = t.truck_id
GROUP  BY t.make,
          t.model_year 


/*Para cada conductor, calcular el revenue total generado y el costo total de combustible en sus viajes. 
Derivar un margen bruto estimado (revenue − costo combustible).*/
SELECT Concat(d.first_name, ' ', d.last_name) AS conductor,
       Sum(l.revenue)                         AS total_revenue,
       Sum(fp.total_cost)                     AS total_cost_fuel,
       Sum(l.revenue) - Sum(fp.total_cost)    AS margen_bruto
FROM   loads AS l
       INNER JOIN trips AS t
               ON l.load_id = t.load_id
       INNER JOIN drivers AS d
               ON t.driver_id = d.driver_id
       INNER JOIN fuel_purchases AS fp
               ON t.trip_id = fp.trip_id
GROUP  BY d.first_name,
          d.last_name ;

/*Identificar los 5 conductores con mayor tasa de incidentes (incidentes por cada 100 viajes realizados). 
Incluir solo conductores con al menos 10 viajes.*/
WITH total_viajes
     AS (SELECT Concat(d.first_name, ' ', d.last_name) AS conductor,
                Count(t.trip_id)                       AS total_viajes,
                Count(si.incident_id)                  AS total_accidentes
         FROM   trips AS t
                INNER JOIN drivers AS d
                        ON t.driver_id = d.driver_id
                LEFT JOIN safety_incidents AS si
                       ON t.trip_id = si.trip_id
         GROUP  BY d.first_name,
                   d.last_name)
SELECT TOP 5 conductor,
             total_viajes,
             total_accidentes,
             ( total_accidentes * 1.0 / total_viajes ) * 100 tasa_incidentes
FROM   total_viajes
ORDER  BY tasa_incidentes DESC;

/*Analizar la evolución mensual del revenue total de cargas. Calcular además la diferencia mes a mes (crecimiento absoluto).*/
WITH revenue
     AS (SELECT Year(load_date)  AS año,
                Month(load_date) AS mes,
                Sum(revenue)     AS total_revenue
         FROM   loads
         GROUP  BY Month(load_date),
                   Year(load_date)),
     variacion_mom
     AS (SELECT año,
                mes,
                total_revenue,
                Lag(total_revenue)
                  OVER(
                    partition BY año
                    ORDER BY año, mes) AS revenue_ant,
                ( ( total_revenue - Lag(total_revenue)
                                      OVER(
                                        partition BY año
                                        ORDER BY año, mes) ) / Lag(
                  total_revenue)
                  OVER(
                    partition BY año
                    ORDER BY año, mes)
                   ) * 100
                                        AS v_MoM
         FROM   revenue)
SELECT *
FROM   variacion_mom;

/*Calcular el costo promedio de combustible por milla para cada camión, 
cruzando el total de galones comprados y el precio promedio por galón contra las millas reales recorridas.*/
WITH costo_por_viaje
     AS (SELECT trip_id,
                Sum(gallons * price_per_gallon) AS costo_total
         FROM   fuel_purchases
         GROUP  BY trip_id)
SELECT tr.truck_id,
       tr.unit_number,
       Concat(tr.make, '-', tr.model_year)                 AS camion,
       Sum(cpv.costo_total) / Sum(t.actual_distance_miles) AS
       costo_promedio_fuel_per_mile
FROM   trips AS t
       INNER JOIN trucks AS tr
               ON t.truck_id = tr.truck_id
       INNER JOIN costo_por_viaje AS cpv
               ON t.trip_id = cpv.trip_id
GROUP  BY tr.truck_id,
          tr.unit_number,
          tr.make,
          tr.model_year
ORDER  BY costo_promedio_fuel_per_mile DESC 

/*Rankear a los conductores dentro de su terminal (home_terminal) por revenue total generado, 
usando una función de ventana. Mostrar el top 3 por terminal.*/
WITH total_revenue_driver
     AS (SELECT Concat(d.first_name, ' ', d.last_name) AS conductor,
                d.home_terminal                        AS terminal,
                Sum(l.revenue)                         AS total_revenue
         FROM   loads AS l
                INNER JOIN trips AS t
                        ON l.load_id = t.load_id
                INNER JOIN drivers AS d
                        ON t.driver_id = d.driver_id
         GROUP  BY d.first_name,
                   d.last_name,
                   d.home_terminal),
     rank_driver
     AS (SELECT conductor,
                terminal,
                total_revenue,
                Rank()
                  OVER(
                    partition BY terminal
                    ORDER BY total_revenue DESC) AS rank_conductores
         FROM   total_revenue_driver)
SELECT conductor,
       terminal,
       total_revenue,
       rank_conductores
FROM   rank_driver
WHERE  rank_conductores <= 3 

/*Calcular el tiempo promedio de detención (detention_minutes) por instalación (facility_id). 
Identificar las 10 instalaciones con mayor detención promedio y su impacto acumulado en horas.*/
SELECT TOP 10
       f.facility_id,
       f.facility_name           AS instalacion,
       Avg(de.detention_minutes) AS min_avg_detention,
       round(sum(de.detention_minutes) / 60.0,2) as total_detention_hours
FROM   delivery_events AS de
       INNER JOIN facilities AS f
               ON de.facility_id = f.facility_id
GROUP  BY f.facility_id,
          f.facility_name
ORDER  BY min_avg_detention desc


/*Para cada ruta, calcular el revenue por milla real recorrida versus la tarifa base de la ruta (base_rate_per_mile). 
Identificar rutas donde el revenue efectivo está por debajo de la tarifa base.*/
WITH rate_per_mile
     AS (SELECT r.route_id,
                Concat(r.origin_city, '->', r.destination_city)   AS ruta,
                ( Sum(l.revenue) / Sum(t.actual_distance_miles) ) AS
                   revenue_efective_per_mile,
                r.base_rate_per_mile
         FROM   loads AS l
                INNER JOIN routes AS r
                        ON l.route_id = r.route_id
                INNER JOIN trips AS t
                        ON l.load_id = t.load_id
         GROUP  BY r.route_id,
                   r.origin_city,
                   r.destination_city,
                   r.base_rate_per_mile)
SELECT route_id,
       ruta,
       revenue_efective_per_mile
FROM   rate_per_mile
WHERE  revenue_efective_per_mile < base_rate_per_mile; 

/*Construir un ranking de los 10 camiones con mayor costo de mantenimiento por milla recorrida.
Combinar el historial de mantenimiento con los viajes para calcular el ratio.*/
WITH costo_mantenimiento
     AS (SELECT truck_id,
                Sum(total_cost) AS costo_total_mantenimiento
         FROM   maintenance_records
         GROUP  BY truck_id),
     millas_por_camion
     AS (SELECT truck_id,
                Sum(actual_distance_miles) AS millas_totales
         FROM   trips
         GROUP  BY truck_id),
     costo_combustile
     AS (SELECT trip_id,
                Sum(gallons * price_per_gallon) AS costo_total_fuel
         FROM   fuel_purchases
         GROUP  BY trip_id),
     fuel_por_camion
     AS (SELECT t.truck_id,
                Sum(cc.costo_total_fuel) AS costo_total_fuel
         FROM   trips AS t
                INNER JOIN costo_combustile AS cc
                        ON t.trip_id = cc.trip_id
         GROUP  BY t.truck_id)
SELECT TOP 10 tr.truck_id,
              tr.make,
              cm.costo_total_mantenimiento / mpc.millas_totales AS
              cost_maintenance_per_mile,
              fc.costo_total_fuel / mpc.millas_totales          AS
              costo_fuel_per_mile,
              ( cm.costo_total_mantenimiento
                + fc.costo_total_fuel ) / mpc.millas_totales    AS
              costo_operativo_total_per_mile
FROM   trucks AS tr
       INNER JOIN costo_mantenimiento AS cm
               ON tr.truck_id = cm.truck_id
       INNER JOIN millas_por_camion AS mpc
               ON tr.truck_id = mpc.truck_id
       INNER JOIN fuel_por_camion AS fc
               ON tr.truck_id = fc.truck_id
GROUP  BY tr.truck_id,
          tr.make,
          cm.costo_total_mantenimiento,
          mpc.millas_totales,
          fc.costo_total_fuel;


/*Calcular el revenue acumulado (running total) por mes usando una función de ventana sobre los datos históricos de cargas.*/

WITH revenue_segmentado
     AS (SELECT Year(load_date)  AS año_load,
                Month(load_date) AS mes_load,
                Sum(revenue)     AS total_revenue
         FROM   loads
         GROUP  BY Year(load_date),
                   Month(load_date))
SELECT año_load,
       mes_load,
       Sum(total_revenue)
         OVER(
           ORDER BY año_load, mes_load) AS revenue_acumulado
FROM   revenue_segmentado
ORDER  BY año_load,
          mes_load 

/*Identificar conductores cuyo MPG promedio en el mes actual es significativamente inferior 
(más de 15%) a su propio promedio histórico. Señal de alerta de rendimiento.*/
select *from driver_monthly_metrics;
with mpg_promedio as (
select
driver_id,
avg(average_mpg) as avg_mpg
from driver_monthly_metrics 
group by driver_id
),
mpg_mes_reciente as (
select
driver_id,
average_mpg as mpg_actual
from driver_monthly_metrics
where month = (select max(month) from driver_monthly_metrics)
)
select 
mp.driver_id,
mp.avg_mpg,
mpg.mpg_actual
from mpg_promedio as mp
inner join mpg_mes_reciente as mpg on mp.driver_id=mpg.driver_id
where mpg.mpg_actual < mp.avg_mpg * 0.85

/*Calcular el análisis RFM simplificado de clientes: Recencia (días desde la última carga), 
Frecuencia (total de cargas) y Monto (revenue total). Clasificar en segmentos High/Mid/Low.*/
with recency as (
select 
customer_id,
DATEDIFF(day,MAX(load_date), (SELECT MAX(load_date) FROM loads)) as days_ultimate_charge 
from loads
group by customer_id
),
frecuencias as (
select
customer_id,
count(load_id) as total_cargas
from loads 
group by customer_id
),
monto as (
select
customer_id,
sum(revenue) total_revenue
from loads 
group by customer_id
),
segmento_rfm as(
 SELECT
 r.customer_id,
 NTILE(3) OVER(ORDER BY r.days_ultimate_charge desc) r_class,
 NTILE(3) OVER(ORDER BY f.total_cargas desc) f_class,
 NTILE(3) OVER(ORDER BY m.total_revenue desc) m_class
 from recency as r
 inner join frecuencias as f on r.customer_id=f.customer_id
 inner join monto as m on r.customer_id=m.customer_id
)
select
c.customer_name,
r.days_ultimate_charge,
f.total_cargas,
m.total_revenue,
CASE 
    WHEN (sr.r_class + sr.f_class + sr.m_class) <= 4 THEN 'High'
    WHEN (sr.r_class + sr.f_class + sr.m_class) <= 7 THEN 'Mid'
    ELSE 'Low'
END AS segmento
from customers as c
inner join recency as r on c.customer_id=r.customer_id
inner join frecuencias as f on c.customer_id=f.customer_id
inner join monto as m on c.customer_id = m.customer_id
inner join segmento_rfm as sr on c.customer_id=sr.customer_id;

/*Detectar camiones que han estado fuera de servicio por mantenimiento durante periodos consecutivos de más de 5 días
(análisis de brechas de disponibilidad).*/
with brecha_tiempo as (
select 
truck_id,
cast(maintenance_date as date) fecha_actual,
lag(cast(maintenance_date as date),1) OVER(Partition by truck_id order by maintenance_date) as fecha_mantenimiento_anterior
from maintenance_records
),
gap as (
select
truck_id,
fecha_actual,
fecha_mantenimiento_anterior,
datediff(day,fecha_mantenimiento_anterior,fecha_actual) as brecha
from brecha_tiempo
)
select 
t.truck_id,
t.make,
g.fecha_actual,
g.fecha_mantenimiento_anterior,
g.brecha
from trucks as t
inner join gap as g on t.truck_id=g.truck_id
where g.brecha <=5;

/*Construir un análisis de cohortes: agrupar los conductores por trimestre de contratación (hire_date) y 
calcular su revenue promedio acumulado a los 6, 12 y 24 meses de antigüedad.*/
WITH base
     AS (SELECT d.driver_id,
                Datepart(quarter, d.hire_date)                AS
                   contrato_trimestre_driver,
                Datediff(month, d.hire_date, t.dispatch_date) AS cohorte,
                l.revenue
         FROM   drivers AS d
                INNER JOIN trips AS t
                        ON d.driver_id = t.driver_id
                INNER JOIN loads AS l
                        ON t.load_id = l.load_id)
SELECT contrato_trimestre_driver,
       Avg(CASE
             WHEN cohorte <= 6 THEN revenue
           END) AS avg_revenue_6m,
       Avg(CASE
             WHEN cohorte <= 12 THEN revenue
           END) AS avg_revenue_12m,
       Avg(CASE
             WHEN cohorte <= 24 THEN revenue
           END) AS avg_revenue_24m
FROM   base
GROUP  BY contrato_trimestre_driver
ORDER  BY contrato_trimestre_driver ASC;

/*Calcular el porcentaje de incidentes prevenibles (preventable_flag) sobre el total por años de experiencia, 
y compararlo contra la media general de la flota usando una subconsulta o CTE.*/
with total_preventable_flag as (
 select
 Case
 WHEN d.years_experience BETWEEN 2  AND 7  THEN 'Novatos'
 WHEN d.years_experience BETWEEN 8  AND 13 THEN 'Intermedios'
 WHEN d.years_experience BETWEEN 14 AND 19 THEN 'Expertos'
 WHEN d.years_experience BETWEEN 20 AND 25 THEN 'Veteranos'
 end AS categoria_experiencia,
 sum(case when si.preventable_flag = 1 then 1 end) as total_prevenibles,
 count(si.incident_id) as total_accidentes,
 (sum(case when si.preventable_flag = 1 then 1 end) * 1.0 / count(si.incident_id)) * 100 as pct_prevenible
 from safety_incidents as si
 inner join drivers as d on si.driver_id=d.driver_id
 group by
 Case
 WHEN d.years_experience BETWEEN 2  AND 7  THEN 'Novatos'
 WHEN d.years_experience BETWEEN 8  AND 13 THEN 'Intermedios'
 WHEN d.years_experience BETWEEN 14 AND 19 THEN 'Expertos'
 WHEN d.years_experience BETWEEN 20 AND 25 THEN 'Veteranos'
 end
),
avg_general_flota as (
select
 avg(cast(preventable_flag as float))*100 as avg_flota
 from safety_incidents 
 )
 SELECT 
    t.categoria_experiencia,
    t.total_prevenibles,
    t.total_accidentes,
    t.pct_prevenible,

    t.pct_prevenible - a.avg_flota AS diferencia_vs_flota,
    CASE 
    WHEN t.pct_prevenible > a.avg_flota THEN 'Por encima de la media'
    WHEN t.pct_prevenible < a.avg_flota THEN 'Por debajo de la media'
    ELSE 'En la media'
END AS comparacion_vs_flota
FROM total_preventable_flag AS t
CROSS JOIN avg_general_flota AS a;

/*Generar un reporte mensual pivoteado que muestre, por tipo de carga (load_type), 
el revenue total en columnas para cada mes del último año.*/
with revenue_total_type as (
select
load_type,
year(load_date) as año,
month(load_date) as mes,
revenue total_revenue
from loads
where load_date between '2024-01-01' and '2024-12-31'
)
select
load_type,
año,
[1] AS Ene,
    [2] AS Feb,
    [3] AS Mar,
    [4] AS Abr,
    [5] AS May,
    [6] AS Jun,
    [7] AS Jul,
    [8] AS Ago,
    [9] AS Sep,
    [10] AS Oct,
    [11] AS Nov,
    [12] AS Dic
from revenue_total_type
pivot (
sum(total_revenue)
for mes in ([1],[2],[3],[4],[5],[6],[7],[8],[9],[10],[11],[12])
) as mes_pivoteado
