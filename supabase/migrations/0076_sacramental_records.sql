-- ==============================================================================
-- 0076_sacramental_records.sql
-- Spec 010: Sacramental Records & Family Digital Archive
-- Immutable sacramental records table, private certificates storage bucket,
-- issue_sacramental_certificate RPC, verify_certificate RPC (privacy protected),
-- and admin_revoke_certificate RPC.
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. Create sacramental_records table
CREATE TABLE IF NOT EXISTS public.sacramental_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sacrament_type TEXT NOT NULL CHECK (sacrament_type IN ('BAPTISM', 'MARRIAGE', 'DEACON_ORDINATION', 'COMMUNION')),
  recipient_name_ar TEXT NOT NULL CHECK (length(trim(recipient_name_ar)) > 0),
  recipient_national_id TEXT,
  recipient_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  sacrament_date DATE NOT NULL,
  officiating_priest_id BIGINT REFERENCES public.priests(id) ON DELETE SET NULL,
  church_location_ar TEXT NOT NULL DEFAULT 'كنيسة السيدة العذراء والأنبا بيشوي',
  registry_book_number TEXT,
  registry_page_number TEXT,
  registry_entry_number TEXT,
  godparents_ar TEXT,
  verification_token TEXT NOT NULL UNIQUE DEFAULT encode(extensions.gen_random_bytes(16), 'hex'),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'REVOKED')),
  revocation_reason TEXT,
  pdf_storage_path TEXT,
  notes TEXT,
  tenant_id BIGINT NOT NULL DEFAULT public.tenant_id(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL
);

-- 2. Indexes
CREATE INDEX IF NOT EXISTS idx_sacramental_records_tenant ON public.sacramental_records(tenant_id);
CREATE INDEX IF NOT EXISTS idx_sacramental_records_user ON public.sacramental_records(recipient_user_id);
CREATE INDEX IF NOT EXISTS idx_sacramental_records_token ON public.sacramental_records(verification_token);
CREATE INDEX IF NOT EXISTS idx_sacramental_records_type ON public.sacramental_records(sacrament_type);
CREATE INDEX IF NOT EXISTS idx_sacramental_records_date ON public.sacramental_records(sacrament_date);

-- 3. Storage Bucket: certificates (private)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('certificates', 'certificates', false, 10485760, ARRAY['application/pdf'])
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DO $$
BEGIN
  ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
EXCEPTION
  WHEN insufficient_privilege THEN NULL;
  WHEN others THEN NULL;
END $$;

-- Storage Grants & Policies
GRANT SELECT ON storage.buckets TO authenticated, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON storage.objects TO authenticated;

DROP POLICY IF EXISTS "Admin manage certificate objects" ON storage.objects;
CREATE POLICY "Admin manage certificate objects"
  ON storage.objects
  FOR ALL
  TO authenticated
  USING (
    bucket_id = 'certificates'
    AND public.is_admin()
  )
  WITH CHECK (
    bucket_id = 'certificates'
    AND public.is_admin()
  );

DROP POLICY IF EXISTS "Authenticated read own certificate objects" ON storage.objects;
CREATE POLICY "Authenticated read own certificate objects"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'certificates'
    AND (
      public.is_admin()
      OR name LIKE public.tenant_id()::text || '/' || auth.uid()::text || '/%'
      OR EXISTS (
        SELECT 1 FROM public.sacramental_records sr
        WHERE sr.pdf_storage_path = storage.objects.name
          AND sr.recipient_user_id = auth.uid()
          AND sr.tenant_id = public.tenant_id()
      )
    )
  );

-- 4. Enable RLS on sacramental_records (Mandatory 2 statements per AGENTS.md)
ALTER TABLE public.sacramental_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins read all sacramental records" ON public.sacramental_records;
CREATE POLICY "Admins read all sacramental records"
  ON public.sacramental_records
  FOR SELECT
  TO authenticated
  USING (
    public.is_admin()
    AND tenant_id = public.tenant_id()
  );

DROP POLICY IF EXISTS "Members read own sacramental records" ON public.sacramental_records;
CREATE POLICY "Members read own sacramental records"
  ON public.sacramental_records
  FOR SELECT
  TO authenticated
  USING (
    recipient_user_id = auth.uid()
    AND tenant_id = public.tenant_id()
  );

-- 5. Revoke client DML and grant granular SELECT
REVOKE INSERT, UPDATE, DELETE ON public.sacramental_records FROM anon, authenticated;
GRANT SELECT ON public.sacramental_records TO authenticated;
GRANT ALL ON public.sacramental_records TO service_role;

-- 6. RPC: issue_sacramental_certificate
CREATE OR REPLACE FUNCTION public.issue_sacramental_certificate(
  p_sacrament_type TEXT,
  p_recipient_name_ar TEXT,
  p_sacrament_date DATE,
  p_church_location_ar TEXT DEFAULT 'كنيسة السيدة العذراء والأنبا بيشوي',
  p_recipient_national_id TEXT DEFAULT NULL,
  p_recipient_user_id UUID DEFAULT NULL,
  p_officiating_priest_id BIGINT DEFAULT NULL,
  p_registry_book_number TEXT DEFAULT NULL,
  p_registry_page_number TEXT DEFAULT NULL,
  p_registry_entry_number TEXT DEFAULT NULL,
  p_godparents_ar TEXT DEFAULT NULL,
  p_pdf_storage_path TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_admin_id UUID := auth.uid();
  v_record_id UUID;
  v_token TEXT;
BEGIN
  -- 1. Authorization Guard
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;

  -- 2. Boundary Validations
  IF p_sacrament_type IS NULL OR p_sacrament_type NOT IN ('BAPTISM', 'MARRIAGE', 'DEACON_ORDINATION', 'COMMUNION') THEN
    RAISE EXCEPTION 'Invalid or missing sacrament type' USING errcode = 'P0001';
  END IF;

  IF p_recipient_name_ar IS NULL OR length(trim(p_recipient_name_ar)) = 0 THEN
    RAISE EXCEPTION 'Recipient name in Arabic is required' USING errcode = 'P0001';
  END IF;

  IF p_sacrament_date IS NULL THEN
    RAISE EXCEPTION 'Sacrament date is required' USING errcode = 'P0001';
  END IF;

  -- 3. Token Generation
  v_token := encode(extensions.gen_random_bytes(16), 'hex');

  -- 4. Insert Record
  INSERT INTO public.sacramental_records (
    sacrament_type,
    recipient_name_ar,
    recipient_national_id,
    recipient_user_id,
    sacrament_date,
    officiating_priest_id,
    church_location_ar,
    registry_book_number,
    registry_page_number,
    registry_entry_number,
    godparents_ar,
    verification_token,
    status,
    pdf_storage_path,
    notes,
    tenant_id,
    created_at,
    created_by
  ) VALUES (
    p_sacrament_type,
    trim(p_recipient_name_ar),
    trim(p_recipient_national_id),
    p_recipient_user_id,
    p_sacrament_date,
    p_officiating_priest_id,
    COALESCE(trim(p_church_location_ar), 'كنيسة السيدة العذراء والأنبا بيشوي'),
    trim(p_registry_book_number),
    trim(p_registry_page_number),
    trim(p_registry_entry_number),
    trim(p_godparents_ar),
    v_token,
    'ACTIVE',
    trim(p_pdf_storage_path),
    trim(p_notes),
    public.tenant_id(),
    now(),
    v_admin_id
  )
  RETURNING id INTO v_record_id;

  RETURN jsonb_build_object(
    'record_id', v_record_id,
    'verification_token', v_token,
    'success', true
  );
END;
$$;

-- 7. RPC: verify_certificate (Public QR Verification)
CREATE OR REPLACE FUNCTION public.verify_certificate(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_rec RECORD;
BEGIN
  IF p_token IS NULL OR length(trim(p_token)) = 0 THEN
    RETURN jsonb_build_object(
      'is_valid', false,
      'error', 'BAD_REQUEST',
      'message_ar', 'رمز التحقق غير صالح'
    );
  END IF;

  SELECT
    sr.id,
    sr.sacrament_type,
    sr.recipient_name_ar,
    sr.sacrament_date,
    p.name AS officiating_priest_name,
    sr.church_location_ar,
    sr.status,
    sr.revocation_reason,
    sr.created_at AS issued_at
  INTO v_rec
  FROM public.sacramental_records sr
  LEFT JOIN public.priests p ON p.id = sr.officiating_priest_id
  WHERE sr.verification_token = trim(p_token);

  IF v_rec.id IS NULL THEN
    RETURN jsonb_build_object(
      'is_valid', false,
      'error', 'NOT_FOUND',
      'message_ar', 'الشهادة غير موجودة أو الرمز غير صحيح'
    );
  END IF;

  IF v_rec.status = 'REVOKED' THEN
    RETURN jsonb_build_object(
      'is_valid', false,
      'status', 'REVOKED',
      'error', 'REVOKED',
      'message_ar', 'تم إلغاء هذه الشهادة رسمياً من قبل الكنيسة',
      'revocation_reason', v_rec.revocation_reason
    );
  END IF;

  -- PRIVACY INVARIANT: STRICTLY DO NOT return national IDs, user IDs, or internal sensitive fields
  RETURN jsonb_build_object(
    'is_valid', true,
    'record_id', v_rec.id,
    'sacrament_type', v_rec.sacrament_type,
    'recipient_name_ar', v_rec.recipient_name_ar,
    'sacrament_date', v_rec.sacrament_date,
    'officiating_priest_name', v_rec.officiating_priest_name,
    'church_location_ar', v_rec.church_location_ar,
    'status', v_rec.status,
    'issued_at', v_rec.issued_at
  );
END;
$$;

-- 8. RPC: admin_revoke_certificate
CREATE OR REPLACE FUNCTION public.admin_revoke_certificate(
  p_record_id UUID,
  p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_admin_id UUID := auth.uid();
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;

  IF p_record_id IS NULL OR p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'Revocation reason is required' USING errcode = 'P0001';
  END IF;

  UPDATE public.sacramental_records
  SET status = 'REVOKED',
      revocation_reason = trim(p_reason)
  WHERE id = p_record_id
    AND tenant_id = public.tenant_id();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sacramental record not found' USING errcode = 'P0002';
  END IF;

  RETURN jsonb_build_object('success', true, 'record_id', p_record_id, 'status', 'REVOKED');
END;
$$;

-- 9. Privilege Hardening
REVOKE ALL ON FUNCTION public.issue_sacramental_certificate(TEXT, TEXT, DATE, TEXT, TEXT, UUID, BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.issue_sacramental_certificate(TEXT, TEXT, DATE, TEXT, TEXT, UUID, BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.admin_revoke_certificate(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_revoke_certificate(UUID, TEXT) TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.verify_certificate(TEXT) TO anon, authenticated, service_role;
