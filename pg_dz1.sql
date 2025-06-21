-- создаем таблицы 

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name TEXT,
    email TEXT,
    role TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


CREATE TABLE users_audit (
    id SERIAL PRIMARY KEY,
    user_id INTEGER,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    changed_by TEXT,
    field_changed TEXT,
    old_value TEXT,
    new_value TEXT
);

--создаем функцию логировния (name, email, role)

CREATE OR REPLACE FUNCTION log_user_audit()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.name IS DISTINCT FROM NEW.name THEN
        INSERT INTO users_audit(user_id, changed_by, field_changed, old_value, new_value)
        VALUES (OLD.id, 'user', 'name', OLD.name, NEW.name);
    END IF;

    IF OLD.email IS DISTINCT FROM NEW.email THEN
        INSERT INTO users_audit(user_id, changed_by, field_changed, old_value, new_value)
        VALUES (OLD.id, 'user', 'email', OLD.email, NEW.email);
    END IF;

    IF OLD.role IS DISTINCT FROM NEW.role THEN
        INSERT INTO users_audit(user_id, changed_by, field_changed, old_value, new_value)
        VALUES (OLD.id, 'user', 'role', OLD.role, NEW.role);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- вешаем тригер на таблицу users

DROP TRIGGER IF EXISTS trg_users_audit ON users;

CREATE TRIGGER trg_users_audit
AFTER UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION log_user_audit();


--- заливаем данные в users

INSERT INTO public.users (name, email, role) VALUES
('Ivan Petrov', 'ivan.petrov@example.com', 'admin'),
('Anna Smirnova', 'anna.smirnova@example.com', 'user'),
('Oleg Ivanov', 'oleg.ivanov@example.com', 'manager'),
('Elena Popova', 'elena.popova@example.com', 'admin'),
('Dmitry Kozlov', 'dmitry.kozlov@example.com', 'user'),
('Svetlana Orlova', 'svetlana.orlova@example.com', 'editor'),
('Alexey Sidorov', 'alexey.sidorov@example.com', 'user'),
('Maria Volkova', 'maria.volkova@example.com', 'manager'),
('Nikolay Egorov', 'nikolay.egorov@example.com', 'admin'),
('Tatyana Fedorova', 'tatyana.fedorova@example.com', 'user'),
('Pavel Lebedev', 'pavel.lebedev@example.com', 'editor'),
('Irina Nikitina', 'irina.nikitina@example.com', 'user'),
('Sergey Mikhailov', 'sergey.mikhailov@example.com', 'manager'),
('Natalia Pavlova', 'natalia.pavlova@example.com', 'admin'),
('Andrey Morozov', 'andrey.morozov@example.com', 'user'),
('Olga Kiseleva', 'olga.kiseleva@example.com', 'manager'),
('Vladimir Gusev', 'vladimir.gusev@example.com', 'user'),
('Ekaterina Solovieva', 'ekaterina.solovieva@example.com', 'editor'),
('Maxim Belov', 'maxim.belov@example.com', 'user'),
('Yulia Zaitseva', 'yulia.zaitseva@example.com', 'admin');


-- обнавляем занчение по id 

UPDATE public.users
SET name = 'Alice Smith', email = 'alice.smith@example.com'
WHERE id = 1;



-- функция експорта изменений в csv

CREATE OR REPLACE FUNCTION export_audit_to_csv() RETURNS void AS $outer$
DECLARE
    path TEXT := '/tmp/users_audit_export_' || to_char(NOW(), 'YYYYMMDD_HH24MI') || '.csv';
BEGIN
    EXECUTE format(
        $inner$
        COPY (
            SELECT user_id, field_changed, old_value, new_value, changed_by, changed_at
            FROM users_audit
            WHERE changed_at >= NOW() - INTERVAL '1 day'
            ORDER BY changed_at
        ) TO '%s' WITH CSV HEADER
        $inner$,
        path
    );
END;
$outer$ LANGUAGE plpgsql;


--запускаем расписание крон на запуск функции export_audit_to_csv

SELECT cron.schedule(
    job_name := 'audit_export_daily',
    schedule := '0 3 * * *',
    command := $$SELECT export_audit_to_csv();$$
);

-- проверка что в cron есть наша задача

SELECT * FROM cron.job;

-- запускаем фукнцию в ручную идем в контейнер проверять файлик

SELECT export_audit_to_csv();



