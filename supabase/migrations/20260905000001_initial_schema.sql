-- ==============================================================================
-- Secure Digital Document Management System — Initial Schema Migration
-- Project: Secure Digital Document Management System for Legal & Investigation Documents
-- Migration: 20260905000001_initial_schema.sql
-- ==============================================================================

-- 1. Enable Required Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "vector" WITH SCHEMA extensions;

-- 2. Timestamp Trigger Function
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Roles Table
CREATE TABLE IF NOT EXISTS public.roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    permissions JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. Departments Table
CREATE TABLE IF NOT EXISTS public.departments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) UNIQUE NOT NULL,
    code VARCHAR(20) UNIQUE NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5. Profiles Table (1:1 with auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    employee_code VARCHAR(50) UNIQUE NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE RESTRICT,
    department_id UUID NOT NULL REFERENCES public.departments(id) ON DELETE RESTRICT,
    phone VARCHAR(50),
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'inactive')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE TRIGGER trg_profiles_updated_at
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- 6. Cases Table
CREATE TABLE IF NOT EXISTS public.cases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_number VARCHAR(100) UNIQUE NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    case_type VARCHAR(100),
    status VARCHAR(30) NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'under_review', 'closed', 'archived')),
    priority VARCHAR(20) NOT NULL DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'critical')),
    created_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    assigned_to UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    closed_at TIMESTAMPTZ
);

CREATE OR REPLACE TRIGGER trg_cases_updated_at
BEFORE UPDATE ON public.cases
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- 7. Documents Table (without current_version_id FK initially to avoid circular dependency)
CREATE TABLE IF NOT EXISTS public.documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
    title VARCHAR(255) NOT NULL,
    document_type VARCHAR(100) NOT NULL,
    storage_bucket VARCHAR(100) NOT NULL,
    storage_path TEXT NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    file_size BIGINT CHECK (file_size >= 0),
    checksum_sha256 VARCHAR(64),
    classification VARCHAR(30) NOT NULL DEFAULT 'confidential' CHECK (classification IN ('public', 'internal', 'confidential', 'restricted', 'highly_restricted')),
    uploaded_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    current_version_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE TRIGGER trg_documents_updated_at
BEFORE UPDATE ON public.documents
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- 8. Document Versions Table
CREATE TABLE IF NOT EXISTS public.document_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id UUID NOT NULL REFERENCES public.documents(id) ON DELETE CASCADE,
    version_no INTEGER NOT NULL CHECK (version_no > 0),
    storage_path TEXT NOT NULL,
    checksum_sha256 VARCHAR(64),
    created_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    change_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_document_version UNIQUE (document_id, version_no)
);

-- Link documents.current_version_id to document_versions(id)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'fk_documents_current_version' AND table_name = 'documents'
    ) THEN
        ALTER TABLE public.documents 
        ADD CONSTRAINT fk_documents_current_version 
        FOREIGN KEY (current_version_id) 
        REFERENCES public.document_versions(id) 
        ON DELETE SET NULL;
    END IF;
END $$;

-- Trigger: auto-create version 1 on new document insert
CREATE OR REPLACE FUNCTION public.handle_new_document_version()
RETURNS TRIGGER AS $$
DECLARE
    v_version_id UUID;
BEGIN
    IF NEW.current_version_id IS NULL THEN
        INSERT INTO public.document_versions (
            document_id,
            version_no,
            storage_path,
            checksum_sha256,
            created_by,
            change_reason
        ) VALUES (
            NEW.id,
            1,
            NEW.storage_path,
            NEW.checksum_sha256,
            NEW.uploaded_by,
            'Initial version uploaded'
        ) RETURNING id INTO v_version_id;

        UPDATE public.documents 
        SET current_version_id = v_version_id 
        WHERE id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_documents_initial_version
AFTER INSERT ON public.documents
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_document_version();

-- 9. Case Documents Junction Table (Many-to-Many)
CREATE TABLE IF NOT EXISTS public.case_documents (
    case_id UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
    document_id UUID NOT NULL REFERENCES public.documents(id) ON DELETE CASCADE,
    relationship_type VARCHAR(50) NOT NULL DEFAULT 'supporting' CHECK (relationship_type IN ('primary', 'supporting', 'evidence', 'reference')),
    added_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (case_id, document_id)
);

-- 10. Evidence Table
CREATE TABLE IF NOT EXISTS public.evidence (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
    document_id UUID REFERENCES public.documents(id) ON DELETE SET NULL,
    evidence_code VARCHAR(100) UNIQUE NOT NULL,
    evidence_type VARCHAR(50) NOT NULL CHECK (evidence_type IN ('physical', 'digital', 'image', 'video', 'document', 'audio', 'device', 'other')),
    description TEXT,
    hash_sha256 VARCHAR(64),
    collected_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    collected_at TIMESTAMPTZ,
    current_custodian UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'stored' CHECK (status IN ('collected', 'stored', 'transferred', 'released', 'archived')),
    storage_bucket VARCHAR(100),
    storage_path TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE TRIGGER trg_evidence_updated_at
BEFORE UPDATE ON public.evidence
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- 11. Document Permissions Table
CREATE TABLE IF NOT EXISTS public.document_permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id UUID NOT NULL REFERENCES public.documents(id) ON DELETE CASCADE,
    profile_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    role_id UUID REFERENCES public.roles(id) ON DELETE CASCADE,
    can_view BOOLEAN NOT NULL DEFAULT false,
    can_download BOOLEAN NOT NULL DEFAULT false,
    can_edit BOOLEAN NOT NULL DEFAULT false,
    can_share BOOLEAN NOT NULL DEFAULT false,
    expires_at TIMESTAMPTZ,
    created_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_perm_target CHECK (
        (profile_id IS NOT NULL AND role_id IS NULL) OR 
        (profile_id IS NULL AND role_id IS NOT NULL)
    ),
    CONSTRAINT uq_perm_profile UNIQUE (document_id, profile_id),
    CONSTRAINT uq_perm_role UNIQUE (document_id, role_id)
);

-- 12. Face Embeddings Table (pgvector 512-dim)
CREATE TABLE IF NOT EXISTS public.face_embeddings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    embedding extensions.vector(512),
    model_version VARCHAR(100) NOT NULL DEFAULT 'ArcFace-r100-v1',
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE TRIGGER trg_face_embeddings_updated_at
BEFORE UPDATE ON public.face_embeddings
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- 13. Audit Logs Table (Append-only audit trail)
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL CHECK (action IN (
        'LOGIN', 'LOGIN_FAILED', 'LOGOUT',
        'DOCUMENT_VIEW', 'DOCUMENT_DOWNLOAD', 'DOCUMENT_UPLOAD', 'DOCUMENT_UPDATE', 'DOCUMENT_DELETE', 'DOCUMENT_SHARE',
        'PERMISSION_GRANT', 'PERMISSION_REVOKE',
        'CASE_CREATE', 'CASE_UPDATE', 'CASE_CLOSE',
        'EVIDENCE_CREATE', 'EVIDENCE_TRANSFER', 'EVIDENCE_UPDATE',
        'PROFILE_UPDATE'
    )),
    entity_type VARCHAR(100),
    entity_id UUID,
    case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
    ip_address INET,
    user_agent TEXT,
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 14. Access Logs Table
CREATE TABLE IF NOT EXISTS public.access_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    event_type VARCHAR(50) NOT NULL CHECK (event_type IN (
        'LOGIN_SUCCESS', 'LOGIN_FAILED', 'LOGOUT', 'SESSION_EXPIRED', 'PASSWORD_RESET', 'FACE_AUTH_SUCCESS', 'FACE_AUTH_FAILED'
    )),
    ip_address INET,
    device_info TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 15. Notifications Table
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE,
    document_id UUID REFERENCES public.documents(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    is_read BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ==============================================================================
-- 16. Security Helper Functions
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.get_current_profile_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT id FROM public.profiles WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.get_current_role_name()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT r.name 
    FROM public.profiles p
    JOIN public.roles r ON p.role_id = r.id
    WHERE p.id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.get_current_department_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT department_id FROM public.profiles WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles p
        JOIN public.roles r ON p.role_id = r.id
        WHERE p.id = auth.uid() AND r.name = 'ADMIN'
    );
$$;

CREATE OR REPLACE FUNCTION public.can_access_case(p_case_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role TEXT;
    v_dept UUID;
    v_uid UUID;
    v_case RECORD;
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RETURN false;
    END IF;

    SELECT r.name, p.department_id INTO v_role, v_dept
    FROM public.profiles p
    JOIN public.roles r ON p.role_id = r.id
    WHERE p.id = v_uid;

    IF v_role = 'ADMIN' THEN
        RETURN true;
    END IF;

    SELECT * INTO v_case FROM public.cases WHERE id = p_case_id;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    -- Directly assigned or created by user
    IF v_case.created_by = v_uid OR v_case.assigned_to = v_uid THEN
        RETURN true;
    END IF;

    -- Department supervisor or officer in same department
    IF v_role IN ('SUPERVISOR', 'INVESTIGATOR', 'OFFICER') AND v_case.department_id = v_dept THEN
        RETURN true;
    END IF;

    RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.can_access_document(p_document_id UUID, p_action TEXT DEFAULT 'view')
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role TEXT;
    v_role_id UUID;
    v_uid UUID;
    v_doc RECORD;
    v_has_explicit_perm BOOLEAN;
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RETURN false;
    END IF;

    SELECT r.name, r.id INTO v_role, v_role_id
    FROM public.profiles p
    JOIN public.roles r ON p.role_id = r.id
    WHERE p.id = v_uid;

    IF v_role = 'ADMIN' THEN
        RETURN true;
    END IF;

    SELECT * INTO v_doc FROM public.documents WHERE id = p_document_id;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    -- Uploader always has access
    IF v_doc.uploaded_by = v_uid THEN
        RETURN true;
    END IF;

    -- Check explicit document_permissions (user-specific or role-specific)
    SELECT EXISTS (
        SELECT 1 FROM public.document_permissions dp
        WHERE dp.document_id = p_document_id
          AND (dp.expires_at IS NULL OR dp.expires_at > now())
          AND (dp.profile_id = v_uid OR dp.role_id = v_role_id)
          AND (
            (p_action = 'view' AND dp.can_view = true) OR
            (p_action = 'download' AND dp.can_download = true) OR
            (p_action = 'edit' AND dp.can_edit = true) OR
            (p_action = 'share' AND dp.can_share = true)
          )
    ) INTO v_has_explicit_perm;

    IF v_has_explicit_perm THEN
        RETURN true;
    END IF;

    -- Highly restricted documents require explicit permission or admin
    IF v_doc.classification = 'highly_restricted' THEN
        RETURN false;
    END IF;

    -- If attached to case, check case access
    IF v_doc.case_id IS NOT NULL THEN
        RETURN public.can_access_case(v_doc.case_id);
    END IF;

    -- Public / internal docs are accessible to authenticated staff
    IF v_doc.classification IN ('public', 'internal') THEN
        RETURN true;
    END IF;

    RETURN false;
END;
$$;

-- Function to record audit events conveniently
CREATE OR REPLACE FUNCTION public.log_audit_event(
    p_action VARCHAR,
    p_entity_type VARCHAR,
    p_entity_id UUID DEFAULT NULL,
    p_case_id UUID DEFAULT NULL,
    p_details JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_log_id UUID;
    v_ip INET;
BEGIN
    BEGIN
        v_ip := inet_client_addr();
    EXCEPTION WHEN OTHERS THEN
        v_ip := NULL;
    END;

    INSERT INTO public.audit_logs (
        actor_id,
        action,
        entity_type,
        entity_id,
        case_id,
        ip_address,
        details
    ) VALUES (
        auth.uid(),
        p_action,
        p_entity_type,
        p_entity_id,
        p_case_id,
        v_ip,
        p_details
    ) RETURNING id INTO v_log_id;

    RETURN v_log_id;
END;
$$;

-- ==============================================================================
-- 17. High-Performance Indexes
-- ==============================================================================

-- Profiles indexes
CREATE INDEX IF NOT EXISTS idx_profiles_role_id ON public.profiles(role_id);
CREATE INDEX IF NOT EXISTS idx_profiles_department_id ON public.profiles(department_id);
CREATE INDEX IF NOT EXISTS idx_profiles_employee_code ON public.profiles(employee_code);
CREATE INDEX IF NOT EXISTS idx_profiles_status ON public.profiles(status);

-- Cases indexes
CREATE INDEX IF NOT EXISTS idx_cases_case_number ON public.cases(case_number);
CREATE INDEX IF NOT EXISTS idx_cases_created_by ON public.cases(created_by);
CREATE INDEX IF NOT EXISTS idx_cases_assigned_to ON public.cases(assigned_to);
CREATE INDEX IF NOT EXISTS idx_cases_department_id ON public.cases(department_id);
CREATE INDEX IF NOT EXISTS idx_cases_status ON public.cases(status);
CREATE INDEX IF NOT EXISTS idx_cases_priority ON public.cases(priority);

-- Documents indexes
CREATE INDEX IF NOT EXISTS idx_documents_case_id ON public.documents(case_id);
CREATE INDEX IF NOT EXISTS idx_documents_uploaded_by ON public.documents(uploaded_by);
CREATE INDEX IF NOT EXISTS idx_documents_document_type ON public.documents(document_type);
CREATE INDEX IF NOT EXISTS idx_documents_classification ON public.documents(classification);
CREATE INDEX IF NOT EXISTS idx_documents_current_version ON public.documents(current_version_id);

-- Document versions indexes
CREATE INDEX IF NOT EXISTS idx_doc_versions_document_id ON public.document_versions(document_id);
CREATE INDEX IF NOT EXISTS idx_doc_versions_created_by ON public.document_versions(created_by);

-- Case documents junction indexes
CREATE INDEX IF NOT EXISTS idx_case_documents_case_id ON public.case_documents(case_id);
CREATE INDEX IF NOT EXISTS idx_case_documents_document_id ON public.case_documents(document_id);

-- Evidence indexes
CREATE INDEX IF NOT EXISTS idx_evidence_case_id ON public.evidence(case_id);
CREATE INDEX IF NOT EXISTS idx_evidence_evidence_code ON public.evidence(evidence_code);
CREATE INDEX IF NOT EXISTS idx_evidence_collected_by ON public.evidence(collected_by);
CREATE INDEX IF NOT EXISTS idx_evidence_current_custodian ON public.evidence(current_custodian);
CREATE INDEX IF NOT EXISTS idx_evidence_status ON public.evidence(status);

-- Document permissions indexes
CREATE INDEX IF NOT EXISTS idx_doc_permissions_doc_id ON public.document_permissions(document_id);
CREATE INDEX IF NOT EXISTS idx_doc_permissions_profile_id ON public.document_permissions(profile_id);
CREATE INDEX IF NOT EXISTS idx_doc_permissions_role_id ON public.document_permissions(role_id);
CREATE INDEX IF NOT EXISTS idx_doc_permissions_expires_at ON public.document_permissions(expires_at);

-- Face embeddings indexes (including HNSW vector cosine similarity index)
CREATE INDEX IF NOT EXISTS idx_face_embeddings_profile_id ON public.face_embeddings(profile_id);
CREATE INDEX IF NOT EXISTS idx_face_embeddings_vector ON public.face_embeddings 
    USING hnsw (embedding extensions.vector_cosine_ops);

-- Audit logs indexes
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor_id ON public.audit_logs(actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON public.audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_logs_case_id ON public.audit_logs(case_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON public.audit_logs(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON public.audit_logs(created_at DESC);

-- Access logs indexes
CREATE INDEX IF NOT EXISTS idx_access_logs_profile_id ON public.access_logs(profile_id);
CREATE INDEX IF NOT EXISTS idx_access_logs_event_type ON public.access_logs(event_type);
CREATE INDEX IF NOT EXISTS idx_access_logs_created_at ON public.access_logs(created_at DESC);

-- Notifications indexes
CREATE INDEX IF NOT EXISTS idx_notifications_profile_id ON public.notifications(profile_id);
CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON public.notifications(is_read);
