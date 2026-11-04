-- 1. Creación e inicialización de la base de datos
CREATE DATABASE "Ecometer";

\c "Ecometer"

-- Función reutilizable para actualización automática de timestamptz (Auditoría)
CREATE OR REPLACE FUNCTION fn_actualizar_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.actualizado_en = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. Tabla de Usuarios
CREATE TABLE usuarios (
    id_usuario INT GENERATED ALWAYS AS IDENTITY,
    nombre VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_usuarios PRIMARY KEY (id_usuario),
    CONSTRAINT uq_usuarios_email UNIQUE (email),
    CONSTRAINT chk_usuarios_email_format CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

-- 3. Tabla de Servicios (Agua, Electricidad)
CREATE TABLE servicios (
    id_servicio INT GENERATED ALWAYS AS IDENTITY,
    nombre_servicio VARCHAR(50) NOT NULL, -- 'Agua', 'Electricidad'[cite: 1]
    unidad_medida VARCHAR(20) NOT NULL,   -- 'm³', 'kWh'
    descripcion TEXT,

    CONSTRAINT pk_servicios PRIMARY KEY (id_servicio),
    CONSTRAINT uq_servicios_nombre UNIQUE (nombre_servicio)
);

-- 4. Tabla de Histórico de Tarifas (Permite cambiar precios sin alterar facturas antiguas)
CREATE TABLE tarifas_servicio (
    id_tarifa INT GENERATED ALWAYS AS IDENTITY,
    id_servicio INT NOT NULL,
    costo_base NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    precio_unidad NUMERIC(10, 4) NOT NULL,
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE,

    CONSTRAINT pk_tarifas PRIMARY KEY (id_tarifa),
    CONSTRAINT fk_tarifas_servicio FOREIGN KEY (id_servicio) 
        REFERENCES servicios(id_servicio) ON DELETE CASCADE,
    CONSTRAINT chk_tarifas_costo_base CHECK (costo_base >= 0),
    CONSTRAINT chk_tarifas_precio CHECK (precio_unidad > 0),
    CONSTRAINT chk_tarifas_rango_fechas CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio)
);

-- 5. Tabla de Medidores
CREATE TABLE medidores (
    id_medidor INT GENERATED ALWAYS AS IDENTITY,
    id_usuario INT NOT NULL,
    id_servicio INT NOT NULL,
    numero_serie VARCHAR(50) NOT NULL,
    ubicacion VARCHAR(150),
    estado VARCHAR(20) NOT NULL DEFAULT 'ACTIVO',
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_medidores PRIMARY KEY (id_medidor),
    CONSTRAINT uq_medidores_serie UNIQUE (numero_serie),
    CONSTRAINT fk_medidores_usuario FOREIGN KEY (id_usuario) 
        REFERENCES usuarios(id_usuario) ON DELETE CASCADE,
    CONSTRAINT fk_medidores_servicio FOREIGN KEY (id_servicio) 
        REFERENCES servicios(id_servicio) ON DELETE RESTRICT,
    CONSTRAINT chk_medidores_estado CHECK (estado IN ('ACTIVO', 'INACTIVO', 'MANTENIMIENTO'))
);

-- 6. Tabla de Historial de Lecturas (para gráficos y consumo entre períodos)[cite: 1]
CREATE TABLE lecturas (
    id_lectura INT GENERATED ALWAYS AS IDENTITY,
    id_medidor INT NOT NULL,
    fecha_lectura TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    lectura_anterior NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    lectura_actual NUMERIC(12, 2) NOT NULL,
    consumo_calculado NUMERIC(12, 2) GENERATED ALWAYS AS (lectura_actual - lectura_anterior) STORED,
    mes SMALLINT NOT NULL,
    anio SMALLINT NOT NULL,

    CONSTRAINT pk_lecturas PRIMARY KEY (id_lectura),
    CONSTRAINT uq_medidor_fecha UNIQUE (id_medidor, fecha_lectura),
    CONSTRAINT fk_lecturas_medidor FOREIGN KEY (id_medidor) 
        REFERENCES medidores(id_medidor) ON DELETE CASCADE,
    CONSTRAINT chk_lecturas_positivas CHECK (lectura_anterior >= 0 AND lectura_actual >= 0),
    CONSTRAINT chk_lecturas_coherencia CHECK (lectura_actual >= lectura_anterior),
    CONSTRAINT chk_lecturas_mes CHECK (mes BETWEEN 1 AND 12),
    CONSTRAINT chk_lecturas_anio CHECK (anio >= 2000)
);

-- 7. Tabla de Detección de Consumos Atípicos / Anomalías (Reglas Matemáticas)[cite: 1]
CREATE TABLE alertas_consumo (
    id_alerta INT GENERATED ALWAYS AS IDENTITY,
    id_lectura INT NOT NULL,
    nivel_anomalia VARCHAR(20) NOT NULL,
    desviacion_porcentaje NUMERIC(6, 2) NOT NULL,
    promedio_historico NUMERIC(12, 2) NOT NULL,
    atendida BOOLEAN NOT NULL DEFAULT FALSE,
    detalles_regla TEXT NOT NULL,
    fecha_deteccion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_alertas PRIMARY KEY (id_alerta),
    CONSTRAINT fk_alertas_lectura FOREIGN KEY (id_lectura) 
        REFERENCES lecturas(id_lectura) ON DELETE CASCADE,
    CONSTRAINT chk_alertas_nivel CHECK (nivel_anomalia IN ('MODERADO', 'ALTO', 'CRITICO')),
    CONSTRAINT chk_alertas_desviacion CHECK (desviacion_porcentaje >= 0),
    CONSTRAINT chk_alertas_promedio CHECK (promedio_historico >= 0)
);

-- 8. Tabla de Estimación de Próxima Factura[cite: 1]
CREATE TABLE estimaciones_factura (
    id_estimacion INT GENERATED ALWAYS AS IDENTITY,
    id_medidor INT NOT NULL,
    mes SMALLINT NOT NULL,
    anio SMALLINT NOT NULL,
    consumo_proyectado NUMERIC(12, 2) NOT NULL,
    monto_estimado NUMERIC(12, 2) NOT NULL,
    fecha_calculo TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_estimaciones PRIMARY KEY (id_estimacion),
    CONSTRAINT uq_estimacion_periodo UNIQUE (id_medidor, anio, mes),
    CONSTRAINT fk_estimaciones_medidor FOREIGN KEY (id_medidor) 
        REFERENCES medidores(id_medidor) ON DELETE CASCADE,
    CONSTRAINT chk_estimaciones_mes CHECK (mes BETWEEN 1 AND 12),
    CONSTRAINT chk_estimaciones_anio CHECK (anio >= 2000),
    CONSTRAINT chk_estimaciones_valores CHECK (consumo_proyectado >= 0 AND monto_estimado >= 0)
);

-- ==============================================================================
-- OPTIMIZACIONES E ÍNDICES (Esenciales para JavaFX & Análisis de Datos)
-- ==============================================================================

-- Búsqueda rápida de lecturas por medidor en orden cronológico (para gráficos)
CREATE INDEX idx_lecturas_medidor_fecha ON lecturas(id_medidor, fecha_lectura DESC);

-- Agrupación rápida por período mensual/anual
CREATE INDEX idx_lecturas_periodo ON lecturas(id_medidor, anio, mes);

-- Índice parcial para consultar únicamente alertas pendientes de revisión
CREATE INDEX idx_alertas_no_atendidas ON alertas_consumo(id_alerta) WHERE atendida = FALSE;

-- ==============================================================================
-- TRIGGERS DE CONTROL
-- ==============================================================================

CREATE TRIGGER trg_usuarios_actualizado
BEFORE UPDATE ON usuarios
FOR EACH ROW EXECUTE FUNCTION fn_actualizar_timestamp();