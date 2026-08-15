# RPC Contracts: Platform Hardening & Bug Fixes

| RPC | Arguments | Return | Access | Error Codes |
| :--- | :--- | :--- | :--- | :--- |
| `book_slot` | `p_slot_id: BIGINT`, `p_quantity: INT`, `p_opt_in: BOOL`, `p_idempotency_key: UUID` | `JSONB` | Authenticated (`USER`, `ADMIN`) | `AUTH_REQUIRED` (28000), `FORBIDDEN` (42501), `INVENTORY_EXHAUSTED` (P0001) |
| `purchase_video` | `p_video_id: BIGINT`, `p_idempotency_key: UUID` | `JSONB` | Authenticated (`USER`, `ADMIN`) | `AUTH_REQUIRED` (28000), `FORBIDDEN` (42501), `NOT_FOUND` (P0002) |
| `claim_event_outbox_batch` | `p_batch_size: INT` | Table (`id`, `event_type`, `payload`, `retry_count`) | `service_role` | None |
| `fn_book_slot_atomic` | `p_slot_id: BIGINT`, `p_quantity: INT`, `p_opt_in: BOOL`, `p_idempotency_key: UUID` | `JSONB` | Authenticated | `INVENTORY_EXHAUSTED` (P0001), `INVALID_QUANTITY` (22023) |