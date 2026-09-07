-- ==============================================================================
-- Secure Digital Document Management System — Supabase Storage Configuration
-- Project: Secure Digital Document Management System for Legal & Investigation Documents
-- Migration: 20260905000003_storage_configuration.sql
-- ==============================================================================

-- 1. Create Private Storage Buckets
INSERT INTO storage.buckets (id, name, public, avif_autodetection, file_size_limit, allowed_mime_types)
VALUES 
    ('case-documents', 'case-documents', false, false, 524288000, NULL), -- 500MB max
    ('evidence-files', 'evidence-files', false, false, 1073741824, NULL), -- 1GB max
    ('temporary-processing', 'temporary-processing', false, false, 104857600, NULL), -- 100MB max
    ('profile-media', 'profile-media', false, false, 10485760, ARRAY['image/jpeg', 'image/png', 'image/webp']) -- 10MB max
ON CONFLICT (id) DO UPDATE SET 
    public = false,
    file_size_limit = EXCLUDED.file_size_limit;

-- 2. Storage Objects Row Level Security Policies
-- (RLS is enabled by default on storage.objects by Supabase)

-- Policy 1: Case Documents - Read Access
DROP POLICY IF EXISTS "Case documents download authorization" ON storage.objects;
CREATE POLICY "Case documents download authorization"
    ON storage.objects FOR SELECT
    TO authenticated
    USING (
        bucket_id = 'case-documents'
        AND (
            public.is_admin()
            OR EXISTS (
                SELECT 1 FROM public.documents d
                WHERE d.storage_bucket = 'case-documents'
                  AND d.storage_path = name
                  AND public.can_access_document(d.id, 'download')
            )
            OR EXISTS (
                SELECT 1 FROM public.document_versions dv
                JOIN public.documents d ON dv.document_id = d.id
                WHERE dv.storage_path = name
                  AND public.can_access_document(d.id, 'download')
            )
        )
    );

-- Policy 2: Case Documents - Upload Access
DROP POLICY IF EXISTS "Case documents upload authorization" ON storage.objects;
CREATE POLICY "Case documents upload authorization"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'case-documents'
        AND public.get_current_role_name() IN ('ADMIN', 'SUPERVISOR', 'INVESTIGATOR', 'OFFICER')
    );

-- Policy 3: Evidence Files - Read Access
DROP POLICY IF EXISTS "Evidence files read authorization" ON storage.objects;
CREATE POLICY "Evidence files read authorization"
    ON storage.objects FOR SELECT
    TO authenticated
    USING (
        bucket_id = 'evidence-files'
        AND (
            public.is_admin()
            OR EXISTS (
                SELECT 1 FROM public.evidence e
                WHERE e.storage_bucket = 'evidence-files'
                  AND e.storage_path = name
                  AND public.can_access_case(e.case_id)
            )
        )
    );

-- Policy 4: Evidence Files - Upload Access
DROP POLICY IF EXISTS "Evidence files upload authorization" ON storage.objects;
CREATE POLICY "Evidence files upload authorization"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'evidence-files'
        AND public.get_current_role_name() IN ('ADMIN', 'SUPERVISOR', 'INVESTIGATOR', 'OFFICER')
    );

-- Policy 5: Temporary Processing - User isolated
DROP POLICY IF EXISTS "Temp processing user isolation" ON storage.objects;
CREATE POLICY "Temp processing user isolation"
    ON storage.objects FOR ALL
    TO authenticated
    USING (
        bucket_id = 'temporary-processing'
        AND (storage.foldername(name))[1] = auth.uid()::text
    )
    WITH CHECK (
        bucket_id = 'temporary-processing'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- Policy 6: Profile Media - Read Access for all authenticated users
DROP POLICY IF EXISTS "Profile media read access" ON storage.objects;
CREATE POLICY "Profile media read access"
    ON storage.objects FOR SELECT
    TO authenticated
    USING (bucket_id = 'profile-media');

-- Policy 7: Profile Media - Manage own avatar
DROP POLICY IF EXISTS "Profile media manage own" ON storage.objects;
CREATE POLICY "Profile media manage own"
    ON storage.objects FOR ALL
    TO authenticated
    USING (
        bucket_id = 'profile-media'
        AND ((storage.foldername(name))[1] = auth.uid()::text OR public.is_admin())
    )
    WITH CHECK (
        bucket_id = 'profile-media'
        AND ((storage.foldername(name))[1] = auth.uid()::text OR public.is_admin())
    );
