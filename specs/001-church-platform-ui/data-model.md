# Phase 1: Data Model & Interface Contracts

### Domain Entities & Relationships

```mermaid
erDiagram
    USERS ||--o{ BOOKINGS : places
    SERVICE_SLOTS ||--o{ BOOKINGS : allocates
    USERS ||--o{ CONFESSION_APPOINTMENTS : books
    PRIEST_PROFILES ||--o{ CONFESSION_APPOINTMENTS : conducts
    AUDIT_LOGS }o--|| USERS : records

    SERVICE_SLOTS {
        uuid id PK
        timestamp service_time
        varchar service_type
        int capacity
        int booked_count
        boolean is_active
    }

    BOOKINGS {
        uuid id PK
        uuid slot_id FK
        uuid user_id FK
        varchar head_of_household_name
        int seats_count
        varchar status
        varchar pass_code
        timestamp created_at
    }

    CONFESSION_APPOINTMENTS {
        uuid id PK
        uuid priest_id FK
        uuid parishioner_id FK
        timestamp appointment_time
        varchar status
        text private_notes
    }
```

### PostgreSQL RPC Contracts

```sql
-- 1. Mass multi-seat booking with FOR UPDATE slot lock
CREATE OR REPLACE FUNCTION book_slot(
    p_slot_id UUID,
    p_user_id UUID,
    p_head_name VARCHAR,
    p_seats_count INT
) RETURNS JSONB;

-- 2. Admin 3-step PIN verification
CREATE OR REPLACE FUNCTION verify_admin_pin(
    p_user_id UUID,
    p_pin_hash VARCHAR
) RETURNS JSONB;

-- 3. Priest Emergency Schedule Override & Auto-Notification
CREATE OR REPLACE FUNCTION emergency_override(
    p_slot_id UUID,
    p_priest_id UUID,
    p_reason TEXT,
    p_new_time TIMESTAMP WITH TIME ZONE DEFAULT NULL
) RETURNS JSONB;
```
