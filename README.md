# Users Audit Pipeline — Техническая документация

🗓️ Дата обновления: 22.06.2025

## 📌 Цель задачи

Реализовать аудит изменений данных пользователей в таблице `users` по полям `name`, `email`, `role`, с логированием всех изменений в отдельную таблицу `users_audit`. Также необходимо ежедневно экспортировать эти данные в CSV-файл внутри Docker-контейнера по пути `/tmp/users_audit_export_<дата>.csv` с помощью `pg_cron`.

---

## 🧱 Структура базы данных

### Основная таблица пользователей

```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name TEXT,
    email TEXT,
    role TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Таблица аудита изменений

```sql
CREATE TABLE users_audit (
    id SERIAL PRIMARY KEY,
    user_id INTEGER,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    changed_by TEXT,
    field_changed TEXT,
    old_value TEXT,
    new_value TEXT
);
```

---

## ⚙️ Логика логирования изменений

### Функция логирования

```sql
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
```

### Триггер на таблицу `users`

```sql
DROP TRIGGER IF EXISTS trg_users_audit ON users;

CREATE TRIGGER trg_users_audit
AFTER UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION log_user_audit();
```

---

## 🧪 Тестовые данные

### Добавление пользователей

```sql
INSERT INTO public.users (name, email, role) VALUES
('Ivan Petrov', 'ivan.petrov@example.com', 'admin'),
('Anna Smirnova', 'anna.smirnova@example.com', 'user'),
('Oleg Ivanov', 'oleg.ivanov@example.com', 'manager'),
('Elena Popova', 'elena.popova@example.com', 'admin'),
('Dmitry Kozlov', 'dmitry.kozlov@example.com', 'user'),
-- ... и т.д. (всего 20 записей)
('Yulia Zaitseva', 'yulia.zaitseva@example.com', 'admin');
```

### Проверка логирования

```sql
UPDATE public.users
SET name = 'Alice Smith', email = 'alice.smith@example.com'
WHERE id = 1;
```

---

## 📝 Экспорт данных за текущий день

### Функция экспорта в CSV

```sql
CREATE OR REPLACE FUNCTION export_audit_to_csv() RETURNS void AS $outer$
DECLARE
    path TEXT := '/tmp/users_audit_export_' || to_char(NOW(), 'YYYYMMDD_HH24MI') || '.csv';
BEGIN
    EXECUTE format(
        $inner$
        COPY (
            SELECT user_id, field_changed, old_value, new_value, changed_by, changed_at
            FROM users_audit
            WHERE changed_at >= NOW()::date
            ORDER BY changed_at
        ) TO '%s' WITH CSV HEADER
        $inner$,
        path
    );
END;
$outer$ LANGUAGE plpgsql;
```

---

## ⏰ Планировщик pg_cron

### Расписание задания

```sql
SELECT cron.schedule(
    job_name := 'audit_export_daily',
    schedule := '0 3 * * *',
    command := $$SELECT export_audit_to_csv();$$
);
```

### Проверка расписания

```sql
SELECT * FROM cron.job;
```

---

## 🧩 Функциональные особенности

- **Поле `changed_by`**: фиксирует источник изменения (в тестовом решении — `'user'`).
- **Историзация**: в таблицу `users_audit` попадают все изменения по полям `name`, `email`, `role`.
- **Отделение аудита от основной таблицы**: исключает избыточные колонки и даёт гибкость хранения.
- **Поддержка pg_cron**: автоматическое выполнение экспорта.

---

## 📦 Пример команды для проверки CSV внутри контейнера

```bash
docker exec -it postgres_db ls /tmp
```

---

## ✅ Ожидаемый результат

| user_id | field_changed | old_value | new_value | changed_by | changed_at |
| ------- | ------------- | --------- | --------- | ---------- | ---------- |
| 1       | name          | Ivan      | Alice     | user       | 2025-06-22 |
| 1       | email         | ...       | ...       | user       | 2025-06-22 |

Файл `/tmp/users_audit_export_20250622_0300.csv` содержит эти строки в формате CSV.
