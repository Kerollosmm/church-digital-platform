-- supabase/tests/run_all.sql: consolidated SQL regression suite.
\set ON_ERROR_STOP on
\ir 0000_health_test.sql
\ir 0001_schema_test.sql
\ir 0002_rls_test.sql
\ir 0003_rbac_test.sql
\ir 0004_portal_read_views_test.sql
\ir 0005_priest_self_assign_test.sql
\ir 0006_announcements_test.sql
\ir 0007_available_slots_test.sql
\ir 0008_booking_state_machine_test.sql
\ir 0009_concurrency_test.sql
\ir 0010_lock_expiry_cron_test.sql
\ir 0011_slots_rls_test.sql
\ir 0012_apply_payment_test.sql
\ir 0014_whatsapp_queue_test.sql
\ir 0015_manual_book_test.sql
\ir 0016_whatsapp_cron_test.sql
\ir 0017_emergency_override_test.sql
\ir 0019_videos_test.sql
\ir 0021_rls_penetration_test.sql
\ir 0022_analytics_aggregates_test.sql
\ir 0023_analytics_views_test.sql
\ir 0024_transition_engine_test.sql
\ir 0025_rbac_helpers_test.sql
\ir 0026_complaints_crypto_test.sql
\ir 0027_event_outbox_test.sql
\ir 0028_paid_amount_test.sql
\ir 0029_fcm_triggers_test.sql
\ir 0031_realtime_publication_test.sql
\ir 0032_offline_sync_test.sql
\ir 0034_admin_pins_test.sql
\ir 0035_concurrency_atomic_test.sql
\ir 0037_seed_data_test.sql
\ir 0039_fixes_regression_test.sql
\ir 0042_social_links_test.sql
\ir 0043_faq_categories_test.sql
\ir 0044_storage_buckets_test.sql
\ir 0045_audit_hardening_test.sql
\ir 0046_payment_refunded_test.sql
\ir 0047_database_optimizations_test.sql
\ir 0048_role_gates_test.sql


