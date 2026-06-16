-- ============================================================
-- Sistema de Predicción de Diabetes
-- Motor: PostgreSQL 15+
-- Fecha: 2026-06-15
-- ============================================================

-- ============================================================
-- ENUMS
-- ============================================================
CREATE TYPE user_role AS ENUM ('admin', 'doctor', 'patient');
CREATE TYPE consultation_status AS ENUM ('pending', 'completed', 'cancelled');
CREATE TYPE image_type AS ENUM ('retina', 'skin');
CREATE TYPE risk_level AS ENUM ('low', 'moderate', 'high');

-- ============================================================
-- 1. users - Autenticación y roles
-- ============================================================
CREATE TABLE users (
    id              SERIAL PRIMARY KEY,
    username        VARCHAR(50) UNIQUE NOT NULL,
    email           VARCHAR(100) UNIQUE NOT NULL,
    password_hash   VARCHAR(255) NOT NULL,
    role            user_role NOT NULL DEFAULT 'patient',
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE users IS 'Usuarios del sistema con autenticación y roles';
COMMENT ON COLUMN users.role IS 'admin, doctor o patient';

-- ============================================================
-- 2. patients - Datos personales + historial médico
-- ============================================================
CREATE TABLE patients (
    id                          SERIAL PRIMARY KEY,
    user_id                     INTEGER REFERENCES users(id) ON DELETE SET NULL,
    first_name                  VARCHAR(50) NOT NULL,
    last_name                   VARCHAR(50) NOT NULL,
    date_of_birth               DATE NOT NULL,
    gender                      CHAR(1) NOT NULL CHECK (gender IN ('M', 'F', 'O')),
    phone                       VARCHAR(20),
    email                       VARCHAR(100),
    -- Historial médico
    family_history_diabetes     BOOLEAN NOT NULL DEFAULT FALSE,
    has_hypertension            BOOLEAN NOT NULL DEFAULT FALSE,
    has_cardiovascular_disease  BOOLEAN NOT NULL DEFAULT FALSE,
    other_conditions            TEXT,
    created_at                  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE patients IS 'Datos personales e historial médico del paciente';
COMMENT ON COLUMN patients.gender IS 'M = Masculino, F = Femenino, O = Otro';
COMMENT ON COLUMN patients.family_history_diabetes IS 'Antecedentes familiares de diabetes';

-- ============================================================
-- 3. consultations - Cada consulta médica realizada
-- ============================================================
CREATE TABLE consultations (
    id                  SERIAL PRIMARY KEY,
    patient_id          INTEGER NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    doctor_id           INTEGER REFERENCES users(id) ON DELETE SET NULL,
    consultation_date   DATE NOT NULL DEFAULT CURRENT_DATE,
    status              consultation_status NOT NULL DEFAULT 'pending',
    notes               TEXT,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE consultations IS 'Registro de cada consulta médica';
COMMENT ON COLUMN consultations.doctor_id IS 'Referencia a users con role = doctor';

-- ============================================================
-- 4. symptom_surveys - Encuesta de síntomas por consulta
-- ============================================================
CREATE TABLE symptom_surveys (
    id                      SERIAL PRIMARY KEY,
    consultation_id         INTEGER NOT NULL UNIQUE REFERENCES consultations(id) ON DELETE CASCADE,
    -- Síntomas clásicos de diabetes
    excessive_thirst        BOOLEAN NOT NULL DEFAULT FALSE,
    frequent_urination      BOOLEAN NOT NULL DEFAULT FALSE,
    fatigue                 BOOLEAN NOT NULL DEFAULT FALSE,
    blurred_vision          BOOLEAN NOT NULL DEFAULT FALSE,
    slow_wound_healing      BOOLEAN NOT NULL DEFAULT FALSE,
    numbness_tingling       BOOLEAN NOT NULL DEFAULT FALSE,
    unexplained_weight_loss BOOLEAN NOT NULL DEFAULT FALSE,
    -- Nivel de glucosa opcional (si se mide en la consulta)
    blood_glucose_level     DECIMAL(6,2),
    survey_date             TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_at              TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE symptom_surveys IS 'Respuestas a la encuesta de síntomas por consulta';
COMMENT ON COLUMN symptom_surveys.blood_glucose_level IS 'Nivel de glucosa en mg/dL (opcional)';

-- ============================================================
-- 5. retina_images - Imágenes de retina (fondos de ojo)
-- ============================================================
CREATE TABLE retina_images (
    id              SERIAL PRIMARY KEY,
    consultation_id INTEGER NOT NULL REFERENCES consultations(id) ON DELETE CASCADE,
    image_path      VARCHAR(500) NOT NULL,
    eye_side        CHAR(1) NOT NULL CHECK (eye_side IN ('L', 'R')),
    capture_date    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    notes           TEXT,
    created_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE retina_images IS 'Imágenes de retina capturadas en la consulta';
COMMENT ON COLUMN retina_images.eye_side IS 'L = Left (izquierdo), R = Right (derecho)';

-- ============================================================
-- 6. skin_images - Imágenes de piel/heridas
-- ============================================================
CREATE TABLE skin_images (
    id              SERIAL PRIMARY KEY,
    consultation_id INTEGER NOT NULL REFERENCES consultations(id) ON DELETE CASCADE,
    image_path      VARCHAR(500) NOT NULL,
    body_area       VARCHAR(100) NOT NULL,
    capture_date    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    notes           TEXT,
    created_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE skin_images IS 'Imágenes de piel o heridas capturadas en la consulta';
COMMENT ON COLUMN skin_images.body_area IS 'Área del cuerpo (ej. foot, leg, arm)';

-- ============================================================
-- 7. image_analyses - Resultados del análisis de imágenes por IA
-- ============================================================
CREATE TABLE image_analyses (
    id              SERIAL PRIMARY KEY,
    image_type      image_type NOT NULL,
    retina_image_id INTEGER REFERENCES retina_images(id) ON DELETE CASCADE,
    skin_image_id   INTEGER REFERENCES skin_images(id) ON DELETE CASCADE,
    analyzed_at     TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    ai_model_version VARCHAR(50),
    findings        JSONB,
    risk_score      DECIMAL(4,3) CHECK (risk_score >= 0 AND risk_score <= 1),
    is_abnormal     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_one_image_type CHECK (
        (image_type = 'retina' AND retina_image_id IS NOT NULL AND skin_image_id IS NULL) OR
        (image_type = 'skin'  AND skin_image_id  IS NOT NULL AND retina_image_id IS NULL)
    )
);

COMMENT ON TABLE image_analyses IS 'Resultados del análisis automatizado de imágenes';
COMMENT ON COLUMN image_analyses.findings IS 'Hallazgos en formato JSON';
COMMENT ON COLUMN image_analyses.risk_score IS 'Puntaje de riesgo de 0.000 a 1.000';

-- ============================================================
-- 8. predictions - Resultado final de la predicción
-- ============================================================
CREATE TABLE predictions (
    id                  SERIAL PRIMARY KEY,
    consultation_id     INTEGER NOT NULL UNIQUE REFERENCES consultations(id) ON DELETE CASCADE,
    survey_risk_score   DECIMAL(4,3) CHECK (survey_risk_score >= 0 AND survey_risk_score <= 1),
    image_risk_score    DECIMAL(4,3) CHECK (image_risk_score >= 0 AND image_risk_score <= 1),
    combined_risk_score DECIMAL(4,3) CHECK (combined_risk_score >= 0 AND combined_risk_score <= 1),
    risk_level          risk_level NOT NULL,
    predicted_diabetes  BOOLEAN NOT NULL,
    confidence          DECIMAL(4,3) CHECK (confidence >= 0 AND confidence <= 1),
    ai_model_version    VARCHAR(50),
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE predictions IS 'Predicción final combinando encuesta + imágenes';
COMMENT ON COLUMN predictions.survey_risk_score IS 'Riesgo calculado solo de la encuesta';
COMMENT ON COLUMN predictions.image_risk_score IS 'Riesgo calculado solo de las imágenes';
COMMENT ON COLUMN predictions.combined_risk_score IS 'Riesgo combinado ponderado';

-- ============================================================
-- ÍNDICES
-- ============================================================
CREATE INDEX idx_patients_user_id       ON patients(user_id);
CREATE INDEX idx_patients_name          ON patients(last_name, first_name);
CREATE INDEX idx_consultations_patient  ON consultations(patient_id);
CREATE INDEX idx_consultations_doctor   ON consultations(doctor_id);
CREATE INDEX idx_consultations_date     ON consultations(consultation_date);
CREATE INDEX idx_retina_consultation    ON retina_images(consultation_id);
CREATE INDEX idx_skin_consultation      ON skin_images(consultation_id);
CREATE INDEX idx_analyses_retina        ON image_analyses(retina_image_id) WHERE retina_image_id IS NOT NULL;
CREATE INDEX idx_analyses_skin          ON image_analyses(skin_image_id) WHERE skin_image_id IS NOT NULL;
CREATE INDEX idx_predictions_risk_level ON predictions(risk_level);
CREATE INDEX idx_predictions_score      ON predictions(combined_risk_score);

-- ============================================================
-- TRIGGERS: Actualizar updated_at automáticamente
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_patients_updated_at
    BEFORE UPDATE ON patients
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- EJEMPLO: Consulta para obtener predicción completa por paciente
-- ============================================================
-- SELECT
--     p.first_name || ' ' || p.last_name AS patient_name,
--     c.consultation_date,
--     ss.excessive_thirst, ss.frequent_urination,
--     pr.risk_level, pr.predicted_diabetes, pr.confidence
-- FROM patients p
-- JOIN consultations c ON c.patient_id = p.id
-- LEFT JOIN symptom_surveys ss ON ss.consultation_id = c.id
-- LEFT JOIN predictions pr ON pr.consultation_id = c.id
-- WHERE p.id = 1
-- ORDER BY c.consultation_date DESC;

-- ============================================================
-- DATOS DE PRUEBA (2 registros completos)
-- ============================================================

-- 1 doctor + 2 pacientes (usuarios)
INSERT INTO users (username, email, password_hash, role) VALUES
('dr.garcia', 'dr.garcia@clinica.com', '$2a$10$dummyhashdoctor', 'doctor'),
('carlos.m', 'carlos.m@email.com', '$2a$10$dummyhashpatient1', 'patient'),
('laura.r', 'laura.r@email.com', '$2a$10$dummyhashpatient2', 'patient');

-- 2 pacientes con historial médico
INSERT INTO patients (user_id, first_name, last_name, date_of_birth, gender, phone, email,
                      family_history_diabetes, has_hypertension, has_cardiovascular_disease)
VALUES
(2, 'Carlos', 'Mendoza', '1978-05-12', 'M', '555-0101', 'carlos.m@email.com',
 TRUE,  TRUE,  FALSE),
(3, 'Laura', 'Rivas',   '1992-11-28', 'F', '555-0202', 'laura.r@email.com',
 FALSE, FALSE, FALSE);

-- 2 consultas (una por paciente)
INSERT INTO consultations (patient_id, doctor_id, consultation_date, status, notes)
VALUES
(1, 1, '2026-06-10', 'completed', 'Paciente refiere sed excesiva y fatiga desde hace 3 meses. Se solicita glucosa en ayunas.'),
(2, 1, '2026-06-12', 'completed', 'Control de rutina. Paciente asintomática, sin antecedentes de riesgo.');

-- 2 encuestas de síntomas
INSERT INTO symptom_surveys (consultation_id, excessive_thirst, frequent_urination, fatigue,
                             blurred_vision, slow_wound_healing, numbness_tingling,
                             unexplained_weight_loss, blood_glucose_level)
VALUES
(1, TRUE, TRUE, TRUE, TRUE, FALSE, TRUE, FALSE, 185.00),
(2, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 92.00);

-- 2 imágenes de retina (una por consulta)
INSERT INTO retina_images (consultation_id, image_path, eye_side, notes)
VALUES
(1, '/images/retina/carlos_m_od_20260610.png', 'R', 'Leve tortuosidad vascular detectada'),
(2, '/images/retina/laura_r_od_20260612.png',  'R', 'Retina sin alteraciones');

-- 2 imágenes de piel (una por consulta)
INSERT INTO skin_images (consultation_id, image_path, body_area, notes)
VALUES
(1, '/images/skin/carlos_m_foot_20260610.png', 'foot', 'Leve enrojecimiento en talón derecho'),
(2, '/images/skin/laura_r_arm_20260612.png',   'arm',  'Piel sin lesiones aparentes');

-- 4 análisis de imágenes (1 por imagen)
INSERT INTO image_analyses (image_type, retina_image_id, skin_image_id, ai_model_version,
                            findings, risk_score, is_abnormal)
VALUES
('retina', 1, NULL, 'diab-v1.2',
 '{"microaneurysms": 2, "hemorrhages": 1, "classification": "NPDR leve"}', 0.720, TRUE),
('skin',   NULL, 1, 'diab-v1.2',
 '{"erythema": true, "ulceration": false, "classification": "posible neuropatia"}', 0.650, TRUE),
('retina', 2, NULL, 'diab-v1.2',
 '{"microaneurysms": 0, "hemorrhages": 0, "classification": "normal"}', 0.050, FALSE),
('skin',   NULL, 2, 'diab-v1.2',
 '{"erythema": false, "ulceration": false, "classification": "normal"}', 0.030, FALSE);

-- 2 predicciones finales
INSERT INTO predictions (consultation_id, survey_risk_score, image_risk_score,
                         combined_risk_score, risk_level, predicted_diabetes, confidence,
                         ai_model_version)
VALUES
(1, 0.857, 0.685, 0.771, 'high', TRUE,  0.890, 'diab-v1.2'),
(2, 0.000, 0.040, 0.020, 'low',  FALSE, 0.950, 'diab-v1.2');
