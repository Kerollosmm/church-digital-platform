# RPC Interface Contracts

| RPC | Parameters | Return | Security / Access | Error Codes |
| :--- | :--- | :--- | :--- | :--- |
| `fn_book_slot_atomic` | `p_slot_id: BIGINT`, `p_quantity: INT`, `p_opt_in: BOOL`, `p_idempotency_key: UUID` | `JSONB` (`booking_id`, `remaining_capacity`) | `SECURITY DEFINER`, authenticated | `AUTH_REQUIRED` (28000), `INVENTORY_EXHAUSTED` (P0001), `INVALID_QUANTITY` (22023) |
| `verify_admin_pin` | `p_pin: TEXT` | `BOOLEAN` | `SECURITY DEFINER`, `is_admin()` | Returns `false` on failure / lockout |
| `set_admin_pin` | `p_pin: TEXT` | `VOID` | `SECURITY DEFINER`, `is_admin()` | `INVALID_PIN` (22023), `FORBIDDEN` (42501) |
| `admin_pin_status` | *None* | `TEXT` (`SET`, `UNSET`, `LOCKED`) | `SECURITY DEFINER`, `is_admin()` | `FORBIDDEN` (42501) |