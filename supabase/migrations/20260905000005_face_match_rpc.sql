-- ==============================================================================
-- Secure Digital Document Management System — Biometric Face Match Function
-- Project: Secure Digital Document Management System for Legal & Investigation Documents
-- Migration: 20260905000005_face_match_rpc.sql
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.match_face_embedding(
    query_embedding extensions.vector(512),
    match_threshold double precision DEFAULT 0.6,
    match_limit integer DEFAULT 5
)
RETURNS TABLE (
    embedding_id UUID,
    profile_id UUID,
    employee_code VARCHAR,
    full_name VARCHAR,
    role_name VARCHAR,
    department_code VARCHAR,
    similarity double precision
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        fe.id AS embedding_id,
        p.id AS profile_id,
        p.employee_code,
        p.full_name,
        r.name::varchar AS role_name,
        d.code::varchar AS department_code,
        (1 - (fe.embedding <=> query_embedding))::double precision AS similarity
    FROM public.face_embeddings fe
    JOIN public.profiles p ON fe.profile_id = p.id
    JOIN public.roles r ON p.role_id = r.id
    JOIN public.departments d ON p.department_id = d.id
    WHERE fe.status = 'active'
      AND p.status = 'active'
      AND (1 - (fe.embedding <=> query_embedding)) >= match_threshold
    ORDER BY fe.embedding <=> query_embedding ASC
    LIMIT match_limit;
END;
$$;
