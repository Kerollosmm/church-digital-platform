BEGIN;
SELECT plan(8);

SELECT hasnt_table('public', 'sunday_school_attendance', 'sunday_school_attendance table dropped');
SELECT hasnt_table('public', 'sunday_school_sessions', 'sunday_school_sessions table dropped');
SELECT hasnt_table('public', 'sunday_school_students', 'sunday_school_students table dropped');
SELECT hasnt_table('public', 'sunday_school_servants', 'sunday_school_servants table dropped');
SELECT hasnt_table('public', 'sunday_school_classes', 'sunday_school_classes table dropped');

SELECT hasnt_function('public', 'get_class_visitation_list', ARRAY['uuid', 'date'], 'get_class_visitation_list RPC dropped');
SELECT hasnt_function('public', 'record_bulk_attendance', ARRAY['uuid', 'date', 'jsonb', 'text'], 'record_bulk_attendance RPC dropped');
SELECT hasnt_function('public', 'is_class_servant', ARRAY['uuid'], 'is_class_servant helper dropped');

SELECT * FROM finish();
ROLLBACK;
