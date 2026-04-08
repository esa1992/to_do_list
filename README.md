# Cross-platform ToDo (Flutter + Node.js)

Полноценный каркас кроссплатформенного приложения задач с клиент-серверной архитектурой:

- **Frontend:** Flutter (Android, iOS, macOS, Windows)
- **Backend:** Node.js + Express + PostgreSQL (облако: Supabase/Neon/RDS)
- **Auth:** JWT + Refresh Token + bcrypt
- **Sync:** инкрементальная синхронизация + offline-first (LWW)
- **Offline cache:** SQLite + очередь операций
- **История:** TaskHistory для всех изменений задач
- **Proxy:** на клиенте, сохраняется локально и применяется ко всем HTTP-запросам

## Структура проекта

```text
.
├── backend
│   ├── package.json
│   ├── tsconfig.json
│   ├── .env.example
│   ├── schema.sql
│   └── src
│       ├── index.ts
│       ├── config.ts
│       ├── db.ts
│       ├── auth.ts
│       ├── middleware.ts
│       ├── routes.auth.ts
│       ├── routes.groups.ts
│       ├── routes.tasks.ts
│       └── routes.sync.ts
└── frontend
    ├── pubspec.yaml
    └── lib
        ├── main.dart
        ├── core
        │   ├── api_client.dart
        │   ├── auth_store.dart
        │   └── proxy_settings.dart
        ├── models
        │   └── models.dart
        └── screens
            ├── login_screen.dart
            ├── tasks_screen.dart
            └── settings_screen.dart
```

## 1) Backend: запуск

1. Создать PostgreSQL БД (можно Supabase).
2. Выполнить SQL из `backend/schema.sql`.
3. Настроить переменные:
   - скопировать `backend/.env.example` -> `backend/.env`
4. Запуск:

```bash
cd backend
npm install
npm run dev
```

Сервер стартует на `http://localhost:8080`.

## 2) Frontend (Flutter): запуск

Требуется установленный Flutter SDK.

```bash
cd frontend
flutter pub get
flutter run
```

Примеры платформ:

```bash
flutter run -d ios
flutter run -d android
flutter run -d macos
flutter run -d windows
```

## 3) Схема API (кратко)

### Auth
- `POST /api/auth/register`
- `POST /api/auth/login`
- `POST /api/auth/refresh`
- `POST /api/auth/logout`

### Groups
- `GET /api/groups`
- `POST /api/groups`
- `PATCH /api/groups/:id`
- `DELETE /api/groups/:id` (каскадно удаляет задачи)
- `POST /api/groups/reorder`

### Tasks
- `GET /api/tasks?groupId=...&q=...&filter=all|active|completed`
- `POST /api/tasks`
- `POST /api/tasks/bulk` (например `Молоко.Фрукты.Овощи`)
- `PATCH /api/tasks/:id`
- `DELETE /api/tasks/:id`
- `POST /api/tasks/reorder`
- `GET /api/tasks/:id/history`
- `POST /api/tasks/:id/rollback` (опциональный откат)

### Sync
- `GET /api/sync/pull?since=ISO_DATE`
- `POST /api/sync/push`

## 4) Реализация требований

- **Изоляция данных пользователей:** все запросы scoped по `user_id` из JWT.
- **История изменений:** при `create/update/delete/complete/reorder` создаётся запись в `task_history`.
- **Подтверждения:** в UI диалоги перед удалением/критичными изменениями.
- **Offline-first:** локальный SQLite-кеш + очередь `pending_ops` + `sync pull/push`.
- **Конфликты:** server-side Last-Write-Wins через `updated_at`.
- **Тёмная тема / минимализм / быстрый ввод:** реализовано в базовом UI.
- **Proxy:** хранится в `SharedPreferences`, применяется через кастомный `HttpClient`.
- **Уведомления:** заготовка для Firebase Messaging и local notifications (дедлайны).
- **Безопасность:** bcrypt, JWT, CORS, HTTPS за reverse proxy (Nginx/Cloudflare).

## 5) Примеры API

Смотри файл `backend/api.examples.http` — готовые HTTP-запросы для тестирования.
