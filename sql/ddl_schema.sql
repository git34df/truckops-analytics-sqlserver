/* ============================================================
   TruckOps — DDL SQL Server
   Motor   : SQL Server 2016 – 2022
   Autor   : Generado con sqlserver-analyst-skill
   Orden   : Maestras → Hechos core → Detalles → Métricas
   ============================================================ */

USE master;
GO

-- Crear la base de datos si no existe
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'TruckOps')
BEGIN
    CREATE DATABASE TruckOps;
    PRINT 'Base de datos TruckOps creada.';
END
GO

USE TruckOps;
GO

/* ============================================================
   0. LIMPIEZA — drop en orden inverso de dependencias
      Útil para re-ejecutar el script desde cero
   ============================================================ */
IF OBJECT_ID('dbo.truck_utilization_metrics', 'U') IS NOT NULL DROP TABLE dbo.truck_utilization_metrics;
IF OBJECT_ID('dbo.driver_monthly_metrics',    'U') IS NOT NULL DROP TABLE dbo.driver_monthly_metrics;
IF OBJECT_ID('dbo.safety_incidents',          'U') IS NOT NULL DROP TABLE dbo.safety_incidents;
IF OBJECT_ID('dbo.maintenance_records',       'U') IS NOT NULL DROP TABLE dbo.maintenance_records;
IF OBJECT_ID('dbo.fuel_purchases',            'U') IS NOT NULL DROP TABLE dbo.fuel_purchases;
IF OBJECT_ID('dbo.delivery_events',           'U') IS NOT NULL DROP TABLE dbo.delivery_events;
IF OBJECT_ID('dbo.trips',                     'U') IS NOT NULL DROP TABLE dbo.trips;
IF OBJECT_ID('dbo.loads',                     'U') IS NOT NULL DROP TABLE dbo.loads;
IF OBJECT_ID('dbo.drivers',                   'U') IS NOT NULL DROP TABLE dbo.drivers;
IF OBJECT_ID('dbo.trailers',                  'U') IS NOT NULL DROP TABLE dbo.trailers;
IF OBJECT_ID('dbo.trucks',                    'U') IS NOT NULL DROP TABLE dbo.trucks;
IF OBJECT_ID('dbo.facilities',                'U') IS NOT NULL DROP TABLE dbo.facilities;
IF OBJECT_ID('dbo.routes',                    'U') IS NOT NULL DROP TABLE dbo.routes;
IF OBJECT_ID('dbo.customers',                 'U') IS NOT NULL DROP TABLE dbo.customers;
GO


/* ============================================================
   1. MAESTRAS / DIMENSIONES
   ============================================================ */

-- ------------------------------------------------------------
-- customers
-- ------------------------------------------------------------
CREATE TABLE dbo.customers (
    customer_id              NVARCHAR(9)     NOT NULL,   -- ej: CUST00001
    customer_name            NVARCHAR(100)   NOT NULL,
    customer_type            NVARCHAR(30)    NOT NULL,   -- Dedicated / Contract / Spot
    credit_terms_days        SMALLINT        NULL,
    primary_freight_type     NVARCHAR(50)    NULL,
    account_status           NVARCHAR(20)    NOT NULL,   -- Active / Inactive
    contract_start_date      DATE            NULL,
    annual_revenue_potential DECIMAL(14, 2)  NULL,

    CONSTRAINT PK_customers PRIMARY KEY CLUSTERED (customer_id)
);
GO

-- ------------------------------------------------------------
-- routes
-- ------------------------------------------------------------
CREATE TABLE dbo.routes (
    route_id               NVARCHAR(8)    NOT NULL,   -- ej: RTE00001
    origin_city            NVARCHAR(60)   NOT NULL,
    origin_state           CHAR(2)        NOT NULL,
    destination_city       NVARCHAR(60)   NOT NULL,
    destination_state      CHAR(2)        NOT NULL,
    typical_distance_miles DECIMAL(8, 2)  NULL,
    base_rate_per_mile     DECIMAL(6, 4)  NULL,
    fuel_surcharge_rate    DECIMAL(5, 4)  NULL,
    typical_transit_days   TINYINT        NULL,

    CONSTRAINT PK_routes PRIMARY KEY CLUSTERED (route_id)
);
GO

-- ------------------------------------------------------------
-- facilities
-- ------------------------------------------------------------
CREATE TABLE dbo.facilities (
    facility_id   NVARCHAR(8)    NOT NULL,   -- ej: FAC00001
    facility_name NVARCHAR(100)  NOT NULL,
    facility_type NVARCHAR(50)   NULL,       -- Cross-Dock / Warehouse / Terminal
    city          NVARCHAR(60)   NOT NULL,
    state         CHAR(2)        NOT NULL,
    latitude      DECIMAL(9, 6)  NULL,
    longitude     DECIMAL(9, 6)  NULL,
    dock_doors    SMALLINT       NULL,
    operating_hours NVARCHAR(30) NULL,       -- ej: 24/7 / 7AM-7PM

    CONSTRAINT PK_facilities PRIMARY KEY CLUSTERED (facility_id)
);
GO

-- ------------------------------------------------------------
-- trucks
-- ------------------------------------------------------------
CREATE TABLE dbo.trucks (
    truck_id              NVARCHAR(8)    NOT NULL,   -- ej: TRK00001
    unit_number           INT            NULL,
    make                  NVARCHAR(50)   NULL,       -- Peterbilt / Kenworth / Freightliner
    model_year            SMALLINT       NULL,
    vin                   NVARCHAR(20)   NULL,
    acquisition_date      DATE           NULL,
    acquisition_mileage   INT            NULL,
    fuel_type             NVARCHAR(20)   NULL,       -- Diesel / CNG
    tank_capacity_gallons SMALLINT       NULL,
    status                NVARCHAR(20)   NOT NULL,   -- Active / Inactive / In Repair
    home_terminal         NVARCHAR(60)   NULL,

    CONSTRAINT PK_trucks PRIMARY KEY CLUSTERED (truck_id)
);
GO

-- ------------------------------------------------------------
-- trailers
-- ------------------------------------------------------------
CREATE TABLE dbo.trailers (
    trailer_id        NVARCHAR(8)   NOT NULL,   -- ej: TRL00001
    trailer_number    INT           NULL,
    trailer_type      NVARCHAR(30)  NULL,       -- Dry Van / Refrigerated / Flatbed
    length_feet       TINYINT       NULL,
    model_year        SMALLINT      NULL,
    vin               NVARCHAR(20)  NULL,
    acquisition_date  DATE          NULL,
    status            NVARCHAR(20)  NOT NULL,
    current_location  NVARCHAR(60)  NULL,

    CONSTRAINT PK_trailers PRIMARY KEY CLUSTERED (trailer_id)
);
GO

-- ------------------------------------------------------------
-- drivers
-- ------------------------------------------------------------
CREATE TABLE dbo.drivers (
    driver_id         NVARCHAR(8)    NOT NULL,   -- ej: DRV00001
    first_name        NVARCHAR(50)   NOT NULL,
    last_name         NVARCHAR(50)   NOT NULL,
    hire_date         DATE           NULL,
    termination_date  DATE           NULL,       -- NULL = activo
    license_number    NVARCHAR(20)   NULL,
    license_state     CHAR(2)        NULL,
    date_of_birth     DATE           NULL,
    home_terminal     NVARCHAR(60)   NULL,
    employment_status NVARCHAR(20)   NOT NULL,   -- Active / Terminated
    cdl_class         CHAR(1)        NULL,       -- A / B
    years_experience  TINYINT        NULL,

    CONSTRAINT PK_drivers PRIMARY KEY CLUSTERED (driver_id)
);
GO


/* ============================================================
   2. HECHOS CORE
   ============================================================ */

-- ------------------------------------------------------------
-- loads  (hecho financiero — depende de customers y routes)
-- ------------------------------------------------------------
CREATE TABLE dbo.loads (
    load_id              NVARCHAR(12)   NOT NULL,   -- ej: LOAD00000001
    customer_id          NVARCHAR(9)    NOT NULL,
    route_id             NVARCHAR(8)    NULL,       -- nullable: cargas fuera de ruta fija
    load_date            DATE           NOT NULL,
    load_type            NVARCHAR(30)   NULL,       -- Dry Van / Refrigerated / Flatbed
    weight_lbs           INT            NULL,
    pieces               SMALLINT       NULL,
    revenue              DECIMAL(10, 2) NULL,
    fuel_surcharge       DECIMAL(8, 2)  NULL,
    accessorial_charges  DECIMAL(8, 2)  NULL,
    load_status          NVARCHAR(20)   NOT NULL,   -- Completed / Cancelled / In Transit
    booking_type         NVARCHAR(20)   NULL,       -- Spot / Dedicated / Contract

    CONSTRAINT PK_loads       PRIMARY KEY CLUSTERED (load_id),
    CONSTRAINT FK_loads_cust  FOREIGN KEY (customer_id) REFERENCES dbo.customers(customer_id),
    CONSTRAINT FK_loads_route FOREIGN KEY (route_id)    REFERENCES dbo.routes(route_id)
);
GO

-- ------------------------------------------------------------
-- trips  (hecho operativo — depende de loads, drivers, trucks, trailers)
-- ------------------------------------------------------------
CREATE TABLE dbo.trips (
    trip_id                NVARCHAR(12)   NOT NULL,   -- ej: TRIP00000001
    load_id                NVARCHAR(12)   NOT NULL,
    driver_id              NVARCHAR(8)    NULL,       -- nullable: trip sin conductor asignado
    truck_id               NVARCHAR(8)    NULL,
    trailer_id             NVARCHAR(8)    NULL,
    dispatch_date          DATE           NOT NULL,
    actual_distance_miles  DECIMAL(8, 2)  NULL,
    actual_duration_hours  DECIMAL(6, 2)  NULL,
    fuel_gallons_used      DECIMAL(8, 2)  NULL,      -- campo calculado — validar vs fuel_purchases
    average_mpg            DECIMAL(5, 2)  NULL,      -- campo calculado — derivado de los anteriores
    idle_time_hours        DECIMAL(6, 2)  NULL,
    trip_status            NVARCHAR(20)   NOT NULL,  -- Completed / Cancelled / In Progress

    CONSTRAINT PK_trips         PRIMARY KEY CLUSTERED (trip_id),
    CONSTRAINT FK_trips_load    FOREIGN KEY (load_id)    REFERENCES dbo.loads(load_id),
    CONSTRAINT FK_trips_driver  FOREIGN KEY (driver_id)  REFERENCES dbo.drivers(driver_id),
    CONSTRAINT FK_trips_truck   FOREIGN KEY (truck_id)   REFERENCES dbo.trucks(truck_id),
    CONSTRAINT FK_trips_trailer FOREIGN KEY (trailer_id) REFERENCES dbo.trailers(trailer_id)
);
GO


/* ============================================================
   3. TABLAS DE DETALLE / TRANSACCIONALES
   ============================================================ */

-- ------------------------------------------------------------
-- delivery_events
-- ------------------------------------------------------------
CREATE TABLE dbo.delivery_events (
    event_id           NVARCHAR(12)   NOT NULL,   -- ej: EVT00000001
    load_id            NVARCHAR(12)   NOT NULL,
    trip_id            NVARCHAR(12)   NOT NULL,
    event_type         NVARCHAR(20)   NOT NULL,   -- Pickup / Delivery
    facility_id        NVARCHAR(8)    NULL,
    scheduled_datetime DATETIME2(3)   NULL,
    actual_datetime    DATETIME2(3)   NULL,
    detention_minutes  INT            NULL,
    on_time_flag       BIT            NULL,
    location_city      NVARCHAR(60)   NULL,
    location_state     CHAR(2)        NULL,

    CONSTRAINT PK_delivery_events      PRIMARY KEY CLUSTERED (event_id),
    CONSTRAINT FK_devt_trip            FOREIGN KEY (trip_id)     REFERENCES dbo.trips(trip_id),
    CONSTRAINT FK_devt_load            FOREIGN KEY (load_id)     REFERENCES dbo.loads(load_id),
    CONSTRAINT FK_devt_facility        FOREIGN KEY (facility_id) REFERENCES dbo.facilities(facility_id)
);
GO

-- ------------------------------------------------------------
-- fuel_purchases
-- ------------------------------------------------------------
CREATE TABLE dbo.fuel_purchases (
    fuel_purchase_id  NVARCHAR(12)   NOT NULL,   -- ej: FUEL00000001
    trip_id           NVARCHAR(12)   NOT NULL,
    truck_id          NVARCHAR(8)    NOT NULL,
    driver_id         NVARCHAR(8)    NULL,        -- nullable: hay registros sin driver en el CSV
    purchase_date     DATETIME2(0)   NOT NULL,
    location_city     NVARCHAR(60)   NULL,
    location_state    CHAR(2)        NULL,
    gallons           DECIMAL(7, 2)  NULL,
    price_per_gallon  DECIMAL(5, 3)  NULL,
    total_cost        DECIMAL(9, 2)  NULL,        -- campo calculado (gallons × price)
    fuel_card_number  NVARCHAR(12)   NULL,        -- dato sensible — evaluar enmascaramiento

    CONSTRAINT PK_fuel_purchases      PRIMARY KEY CLUSTERED (fuel_purchase_id),
    CONSTRAINT FK_fuel_trip           FOREIGN KEY (trip_id)   REFERENCES dbo.trips(trip_id),
    CONSTRAINT FK_fuel_truck          FOREIGN KEY (truck_id)  REFERENCES dbo.trucks(truck_id),
    CONSTRAINT FK_fuel_driver         FOREIGN KEY (driver_id) REFERENCES dbo.drivers(driver_id)
);
GO

-- ------------------------------------------------------------
-- maintenance_records
-- ------------------------------------------------------------
CREATE TABLE dbo.maintenance_records (
    maintenance_id    NVARCHAR(12)   NOT NULL,   -- ej: MAINT00000001
    truck_id          NVARCHAR(8)    NOT NULL,
    maintenance_date  DATE           NOT NULL,
    maintenance_type  NVARCHAR(50)   NULL,        -- Inspection / Tire / Oil / Engine
    odometer_reading  INT            NULL,
    labor_hours       DECIMAL(5, 2)  NULL,
    labor_cost        DECIMAL(9, 2)  NULL,
    parts_cost        DECIMAL(9, 2)  NULL,
    total_cost        DECIMAL(9, 2)  NULL,        -- campo calculado
    facility_location NVARCHAR(60)   NULL,
    downtime_hours    DECIMAL(6, 2)  NULL,
    service_description NVARCHAR(200) NULL,

    CONSTRAINT PK_maintenance        PRIMARY KEY CLUSTERED (maintenance_id),
    CONSTRAINT FK_maint_truck        FOREIGN KEY (truck_id) REFERENCES dbo.trucks(truck_id)
);
GO

-- ------------------------------------------------------------
-- safety_incidents
-- ------------------------------------------------------------
CREATE TABLE dbo.safety_incidents (
    incident_id          NVARCHAR(12)   NOT NULL,   -- ej: INC00000001
    trip_id              NVARCHAR(12)   NOT NULL,
    truck_id             NVARCHAR(8)    NOT NULL,
    driver_id            NVARCHAR(8)    NOT NULL,
    incident_date        DATETIME2(0)   NOT NULL,
    incident_type        NVARCHAR(60)   NULL,        -- Moving Violation / Accident / Near Miss
    location_city        NVARCHAR(60)   NULL,
    location_state       CHAR(2)        NULL,
    at_fault_flag        BIT            NULL,
    injury_flag          BIT            NULL,
    vehicle_damage_cost  DECIMAL(10, 2) NULL,
    cargo_damage_cost    DECIMAL(10, 2) NULL,
    claim_amount         DECIMAL(10, 2) NULL,
    preventable_flag     BIT            NULL,
    description          NVARCHAR(300)  NULL,

    CONSTRAINT PK_safety_incidents   PRIMARY KEY CLUSTERED (incident_id),
    CONSTRAINT FK_inc_trip           FOREIGN KEY (trip_id)   REFERENCES dbo.trips(trip_id),
    CONSTRAINT FK_inc_truck          FOREIGN KEY (truck_id)  REFERENCES dbo.trucks(truck_id),
    CONSTRAINT FK_inc_driver         FOREIGN KEY (driver_id) REFERENCES dbo.drivers(driver_id)
);
GO


/* ============================================================
   4. MÉTRICAS PRE-AGREGADAS
      PK compuesta (entidad + mes) — no referencian trips directamente
   ============================================================ */

-- ------------------------------------------------------------
-- driver_monthly_metrics
-- ------------------------------------------------------------
CREATE TABLE dbo.driver_monthly_metrics (
    driver_id              NVARCHAR(8)    NOT NULL,
    month                  DATE           NOT NULL,   -- primer día del mes: 2022-01-01
    trips_completed        SMALLINT       NULL,
    total_miles            INT            NULL,
    total_revenue          DECIMAL(12, 2) NULL,
    average_mpg            DECIMAL(5, 2)  NULL,
    total_fuel_gallons     DECIMAL(10, 2) NULL,
    on_time_delivery_rate  DECIMAL(5, 3)  NULL,       -- 0.000 – 1.000
    average_idle_hours     DECIMAL(5, 2)  NULL,

    CONSTRAINT PK_driver_monthly     PRIMARY KEY CLUSTERED (driver_id, month),
    CONSTRAINT FK_dmm_driver         FOREIGN KEY (driver_id) REFERENCES dbo.drivers(driver_id)
);
GO

-- ------------------------------------------------------------
-- truck_utilization_metrics
-- ------------------------------------------------------------
CREATE TABLE dbo.truck_utilization_metrics (
    truck_id             NVARCHAR(8)    NOT NULL,
    month                DATE           NOT NULL,
    trips_completed      SMALLINT       NULL,
    total_miles          INT            NULL,
    total_revenue        DECIMAL(12, 2) NULL,
    average_mpg          DECIMAL(5, 2)  NULL,
    maintenance_events   TINYINT        NULL,
    maintenance_cost     DECIMAL(10, 2) NULL,
    downtime_hours       DECIMAL(7, 2)  NULL,
    utilization_rate     DECIMAL(5, 3)  NULL,         -- 0.000 – 1.000

    CONSTRAINT PK_truck_utilization  PRIMARY KEY CLUSTERED (truck_id, month),
    CONSTRAINT FK_tum_truck          FOREIGN KEY (truck_id) REFERENCES dbo.trucks(truck_id)
);
GO


/* ============================================================
   5. ÍNDICES NON-CLUSTERED
      Cubren los JOINs y filtros más frecuentes en análisis
   ============================================================ */

-- loads: filtros por fecha y cliente
CREATE NONCLUSTERED INDEX IX_loads_load_date    ON dbo.loads (load_date)    INCLUDE (customer_id, revenue, load_status);
CREATE NONCLUSTERED INDEX IX_loads_customer_id  ON dbo.loads (customer_id)  INCLUDE (load_date, revenue, booking_type);

-- trips: filtros por fecha y conductor/camión
CREATE NONCLUSTERED INDEX IX_trips_dispatch_date ON dbo.trips (dispatch_date) INCLUDE (driver_id, truck_id, trip_status);
CREATE NONCLUSTERED INDEX IX_trips_driver_id     ON dbo.trips (driver_id)     INCLUDE (dispatch_date, actual_distance_miles, fuel_gallons_used);
CREATE NONCLUSTERED INDEX IX_trips_truck_id      ON dbo.trips (truck_id)      INCLUDE (dispatch_date, actual_distance_miles, idle_time_hours);

-- delivery_events: filtros OTD por viaje y fecha
CREATE NONCLUSTERED INDEX IX_devt_trip_id         ON dbo.delivery_events (trip_id)           INCLUDE (event_type, on_time_flag, detention_minutes);
CREATE NONCLUSTERED INDEX IX_devt_scheduled_date  ON dbo.delivery_events (scheduled_datetime) INCLUDE (trip_id, on_time_flag, event_type);

-- fuel_purchases: análisis de costo por fecha y camión
CREATE NONCLUSTERED INDEX IX_fuel_purchase_date   ON dbo.fuel_purchases (purchase_date) INCLUDE (truck_id, driver_id, gallons, total_cost);
CREATE NONCLUSTERED INDEX IX_fuel_truck_id        ON dbo.fuel_purchases (truck_id)      INCLUDE (purchase_date, gallons, total_cost);

-- maintenance_records: historial por camión y fecha
CREATE NONCLUSTERED INDEX IX_maint_truck_date     ON dbo.maintenance_records (truck_id, maintenance_date) INCLUDE (maintenance_type, total_cost, downtime_hours);

-- safety_incidents: análisis por conductor y fecha
CREATE NONCLUSTERED INDEX IX_inc_driver_date      ON dbo.safety_incidents (driver_id, incident_date) INCLUDE (incident_type, claim_amount, preventable_flag);

GO


/* ============================================================
   6. VERIFICACIÓN RÁPIDA — ejecutar al finalizar la carga
   ============================================================ */
SELECT
    t.name          AS tabla,
    p.rows          AS filas_cargadas
FROM sys.tables        t
JOIN sys.partitions    p ON t.object_id = p.object_id AND p.index_id IN (0, 1)
WHERE t.schema_id = SCHEMA_ID('dbo')
ORDER BY p.rows DESC;
GO

PRINT 'DDL TruckOps ejecutado correctamente.';
GO




