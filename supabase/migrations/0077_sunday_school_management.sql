-- ==============================================================================
-- 0077_sunday_school_management.sql
-- Spec 011: Servants & Sunday School Management
-- Classes, Servant Assignments, Student Rosters, Sessions, and Attendance Tracking.
-- ==============================================================================

-- 1. Sunday School Classes Table
CREATE TABLE IF NOT EXISTS public.sunday_school_classes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name_ar TEXT NOT NULL,
  stage TEXT NOT NULL CHECK (stage IN ('NURSERY', 'PRIMARY', 'PREPARATORY', 'SECONDARY', 'UNIVERSITY', 'GENERAL')),
  grade_level INT,
  academic_year TEXT NOT NULL DEFAULT '2025-2026',
  tenant_id BIGINT NOT NULL DEFAULT public.tenant_id(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Sunday School Servants Table
CREATE TABLE IF NOT EXISTS public.sunday_school_servants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id UUID NOT NULL REFERENCES public.sunday_school_classes(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'SERVANT' CHECK (role IN ('LEADER', 'SERVANT', 'ASSISTANT')),
  is_active BOOLEAN NOT NULL DEFAULT true,
  tenant_id BIGINT NOT NULL DEFAULT public.tenant_id(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT unique_servant_per_class UNIQUE (class_id, user_id)
);

-- 3. Sunday School Students Table
CREATE TABLE IF NOT EXISTS public.sunday_school_students (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id UUID NOT NULL REFERENCES public.sunday_school_classes(id) ON DELETE CASCADE,
  full_name_ar TEXT NOT NULL,
  birth_date DATE,
  phone TEXT,
  parent_phone TEXT,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  notes TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  tenant_id BIGINT NOT NULL DEFAULT public.tenant_id(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. Sunday School Sessions Table
CREATE TABLE IF NOT EXISTS public.sunday_school_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id UUID NOT NULL REFERENCES public.sunday_school_classes(id) ON DELETE CASCADE,
  session_date DATE NOT NULL,
  topic_title_ar TEXT,
  servant_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  tenant_id BIGINT NOT NULL DEFAULT public.tenant_id(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT unique_session_per_class_date UNIQUE (class_id, session_date)
);

-- 5. Sunday School Attendance Table
CREATE TABLE IF NOT EXISTS public.sunday_school_attendance (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id UUID NOT NULL REFERENCES public.sunday_school_classes(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES public.sunday_school_students(id) ON DELETE CASCADE,
  session_date DATE NOT NULL,
  status TEXT NOT NULL DEFAULT 'PRESENT' CHECK (status IN ('PRESENT', 'ABSENT', 'EXCUSED')),
  recorded_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  notes TEXT,
  tenant_id BIGINT NOT NULL DEFAULT public.tenant_id(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT unique_student_session_attendance UNIQUE (student_id, session_date)
);

-- 6. Indexes
CREATE INDEX IF NOT EXISTS idx_sunday_school_classes_tenant ON public.sunday_school_classes(tenant_id);
CREATE INDEX IF NOT EXISTS idx_sunday_school_servants_class ON public.sunday_school_servants(class_id);
CREATE INDEX IF NOT EXISTS idx_sunday_school_servants_user ON public.sunday_school_servants(user_id);
CREATE INDEX IF NOT EXISTS idx_sunday_school_students_class ON public.sunday_school_students(class_id);
CREATE INDEX IF NOT EXISTS idx_sunday_school_students_tenant ON public.sunday_school_students(tenant_id);
CREATE INDEX IF NOT EXISTS idx_sunday_school_sessions_class ON public.sunday_school_sessions(class_id);
CREATE INDEX IF NOT EXISTS idx_sunday_school_attendance_class ON public.sunday_school_attendance(class_id);
CREATE INDEX IF NOT EXISTS idx_sunday_school_attendance_student ON public.sunday_school_attendance(student_id);
CREATE INDEX IF NOT EXISTS idx_sunday_school_attendance_date ON public.sunday_school_attendance(session_date);

-- 7. Enable RLS (Mandatory 2 statements per table)
ALTER TABLE public.sunday_school_classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sunday_school_servants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sunday_school_students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sunday_school_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sunday_school_attendance ENABLE ROW LEVEL SECURITY;

-- 8. Policies
-- Classes
DROP POLICY IF EXISTS "Authenticated read sunday_school_classes" ON public.sunday_school_classes;
CREATE POLICY "Authenticated read sunday_school_classes" ON public.sunday_school_classes
  FOR SELECT TO anon, authenticated
  USING (tenant_id = public.tenant_id());

DROP POLICY IF EXISTS "Admin manage sunday_school_classes" ON public.sunday_school_classes;
CREATE POLICY "Admin manage sunday_school_classes" ON public.sunday_school_classes
  FOR ALL TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id())
  WITH CHECK (public.is_admin() AND tenant_id = public.tenant_id());

-- Servants
DROP POLICY IF EXISTS "Authenticated read sunday_school_servants" ON public.sunday_school_servants;
CREATE POLICY "Authenticated read sunday_school_servants" ON public.sunday_school_servants
  FOR SELECT TO anon, authenticated
  USING (tenant_id = public.tenant_id());

DROP POLICY IF EXISTS "Admin manage sunday_school_servants" ON public.sunday_school_servants;
CREATE POLICY "Admin manage sunday_school_servants" ON public.sunday_school_servants
  FOR ALL TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id())
  WITH CHECK (public.is_admin() AND tenant_id = public.tenant_id());

-- Students
DROP POLICY IF EXISTS "Authenticated read sunday_school_students" ON public.sunday_school_students;
CREATE POLICY "Authenticated read sunday_school_students" ON public.sunday_school_students
  FOR SELECT TO anon, authenticated
  USING (tenant_id = public.tenant_id());

DROP POLICY IF EXISTS "Admin manage sunday_school_students" ON public.sunday_school_students;
CREATE POLICY "Admin manage sunday_school_students" ON public.sunday_school_students
  FOR ALL TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id())
  WITH CHECK (public.is_admin() AND tenant_id = public.tenant_id());

-- Sessions
DROP POLICY IF EXISTS "Authenticated read sunday_school_sessions" ON public.sunday_school_sessions;
CREATE POLICY "Authenticated read sunday_school_sessions" ON public.sunday_school_sessions
  FOR SELECT TO anon, authenticated
  USING (tenant_id = public.tenant_id());

DROP POLICY IF EXISTS "Admin manage sunday_school_sessions" ON public.sunday_school_sessions;
CREATE POLICY "Admin manage sunday_school_sessions" ON public.sunday_school_sessions
  FOR ALL TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id())
  WITH CHECK (public.is_admin() AND tenant_id = public.tenant_id());

-- Attendance
DROP POLICY IF EXISTS "Authenticated read sunday_school_attendance" ON public.sunday_school_attendance;
CREATE POLICY "Authenticated read sunday_school_attendance" ON public.sunday_school_attendance
  FOR SELECT TO anon, authenticated
  USING (tenant_id = public.tenant_id());

DROP POLICY IF EXISTS "Admin manage sunday_school_attendance" ON public.sunday_school_attendance;
CREATE POLICY "Admin manage sunday_school_attendance" ON public.sunday_school_attendance
  FOR ALL TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id())
  WITH CHECK (public.is_admin() AND tenant_id = public.tenant_id());

-- 9. DML Permissions & Revocations
REVOKE INSERT, UPDATE, DELETE ON public.sunday_school_attendance, public.sunday_school_classes, public.sunday_school_servants, public.sunday_school_students, public.sunday_school_sessions FROM anon, authenticated;
GRANT SELECT ON public.sunday_school_attendance, public.sunday_school_classes, public.sunday_school_servants, public.sunday_school_students, public.sunday_school_sessions TO anon, authenticated;
GRANT ALL ON public.sunday_school_attendance, public.sunday_school_classes, public.sunday_school_servants, public.sunday_school_students, public.sunday_school_sessions TO service_role;

-- 10. Helper Function: is_class_servant
CREATE OR REPLACE FUNCTION public.is_class_servant(p_class_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL OR p_class_id IS NULL THEN
    RETURN false;
  END IF;
  RETURN EXISTS (
    SELECT 1
    FROM public.sunday_school_servants
    WHERE class_id = p_class_id
      AND user_id = auth.uid()
      AND is_active = true
      AND tenant_id = public.tenant_id()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.is_class_servant(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_class_servant(UUID) TO authenticated, service_role;

-- 11. Stored Procedure: record_bulk_attendance
CREATE OR REPLACE FUNCTION public.record_bulk_attendance(
  p_class_id UUID,
  p_session_date DATE,
  p_records JSONB,
  p_session_title TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user UUID := auth.uid();
  v_elem JSONB;
  v_student_id UUID;
  v_status TEXT;
  v_notes TEXT;
  v_count INT := 0;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED' USING errcode = '28000';
  END IF;

  IF NOT (public.is_admin() OR public.is_class_servant(p_class_id)) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;

  IF p_class_id IS NULL OR p_session_date IS NULL OR p_records IS NULL THEN
    RAISE EXCEPTION 'BAD_REQUEST' USING errcode = 'P0001';
  END IF;

  IF p_session_date > (CURRENT_DATE + interval '1 day') THEN
    RAISE EXCEPTION 'BAD_REQUEST' USING errcode = 'P0001';
  END IF;

  -- Validate class existence
  IF NOT EXISTS (
    SELECT 1 FROM public.sunday_school_classes
    WHERE id = p_class_id AND tenant_id = public.tenant_id()
  ) THEN
    RAISE EXCEPTION 'CLASS_NOT_FOUND' USING errcode = 'P0001';
  END IF;

  -- Create or update session metadata
  INSERT INTO public.sunday_school_sessions (
    class_id,
    session_date,
    topic_title_ar,
    servant_id,
    tenant_id
  ) VALUES (
    p_class_id,
    p_session_date,
    p_session_title,
    v_user,
    public.tenant_id()
  )
  ON CONFLICT (class_id, session_date) DO UPDATE SET
    topic_title_ar = COALESCE(EXCLUDED.topic_title_ar, sunday_school_sessions.topic_title_ar),
    servant_id = EXCLUDED.servant_id;

  -- Process student attendance records
  FOR v_elem IN SELECT * FROM jsonb_array_elements(p_records)
  LOOP
    v_student_id := (v_elem->>'student_id')::uuid;
    v_status := COALESCE(v_elem->>'status', 'PRESENT');
    v_notes := v_elem->>'notes';

    IF v_student_id IS NULL THEN
      RAISE EXCEPTION 'BAD_REQUEST' USING errcode = 'P0001';
    END IF;

    IF v_status NOT IN ('PRESENT', 'ABSENT', 'EXCUSED') THEN
      RAISE EXCEPTION 'BAD_REQUEST' USING errcode = 'P0001';
    END IF;

    -- Validate student belongs to class
    IF NOT EXISTS (
      SELECT 1 FROM public.sunday_school_students
      WHERE id = v_student_id
        AND class_id = p_class_id
        AND is_active = true
        AND tenant_id = public.tenant_id()
    ) THEN
      RAISE EXCEPTION 'STUDENT_NOT_IN_CLASS' USING errcode = 'P0001';
    END IF;

    -- Upsert attendance record
    INSERT INTO public.sunday_school_attendance (
      class_id,
      student_id,
      session_date,
      status,
      recorded_by,
      notes,
      tenant_id
    ) VALUES (
      p_class_id,
      v_student_id,
      p_session_date,
      v_status,
      v_user,
      v_notes,
      public.tenant_id()
    )
    ON CONFLICT (student_id, session_date) DO UPDATE SET
      status = EXCLUDED.status,
      notes = EXCLUDED.notes,
      recorded_by = EXCLUDED.recorded_by;

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'recorded_count', v_count,
    'session_date', p_session_date
  );
END;
$$;

REVOKE ALL ON FUNCTION public.record_bulk_attendance(UUID, DATE, JSONB, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_bulk_attendance(UUID, DATE, JSONB, TEXT) TO authenticated, service_role;
