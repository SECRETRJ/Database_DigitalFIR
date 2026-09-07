-- ==============================================================================
-- Secure Digital Document Management System — Row Level Security (RLS)
-- Project: Secure Digital Document Management System for Legal & Investigation Documents
-- Migration: 20260905000002_row_level_security.sql
-- ==============================================================================

-- 1. Enable RLS on all 13 core tables
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.case_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.face_embeddings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.access_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- ==============================================================================
-- 2. Roles Table Policies
-- ==============================================================================
DROP POLICY IF EXISTS "Allow authenticated users to read roles" ON public.roles;
CREATE POLICY "Allow authenticated users to read roles"
    ON public.roles FOR SELECT
    TO authenticated
    USING (true);

DROP POLICY IF EXISTS "Allow admins to manage roles" ON public.roles;
CREATE POLICY "Allow admins to manage roles"
    ON public.roles FOR ALL
    TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- ==============================================================================
-- 3. Departments Table Policies
-- ==============================================================================
DROP POLICY IF EXISTS "Allow authenticated users to read departments" ON public.departments;
CREATE POLICY "Allow authenticated users to read departments"
    ON public.departments FOR SELECT
    TO authenticated
    USING (true);

DROP POLICY IF EXISTS "Allow admins to manage departments" ON public.departments;
CREATE POLICY "Allow admins to manage departments"
    ON public.departments FOR ALL
    TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- ==============================================================================
-- 4. Profiles Table Policies
-- ==============================================================================
-- Users can see their own profile or active profiles across the organization
DROP POLICY IF EXISTS "Allow users to view profiles" ON public.profiles;
CREATE POLICY "Allow users to view profiles"
    ON public.profiles FOR SELECT
    TO authenticated
    USING (
        id = auth.uid() 
        OR status = 'active'
        OR public.is_admin()
    );

-- Insert restricted to admins or user matching their auth.uid() during onboarding
DROP POLICY IF EXISTS "Allow profile creation" ON public.profiles;
CREATE POLICY "Allow profile creation"
    ON public.profiles FOR INSERT
    TO authenticated
    WITH CHECK (
        id = auth.uid() OR public.is_admin()
    );

-- Self-update of profile (restricted from escalating role/status by trigger or admin check)
DROP POLICY IF EXISTS "Allow users to update own profile or admin" ON public.profiles;
CREATE POLICY "Allow users to update own profile or admin"
    ON public.profiles FOR UPDATE
    TO authenticated
    USING (
        id = auth.uid() OR public.is_admin()
    )
    WITH CHECK (
        id = auth.uid() OR public.is_admin()
    );

DROP POLICY IF EXISTS "Allow admins to delete profiles" ON public.profiles;
CREATE POLICY "Allow admins to delete profiles"
    ON public.profiles FOR DELETE
    TO authenticated
    USING (public.is_admin());

-- Protect against role escalation by non-admins
CREATE OR REPLACE FUNCTION public.protect_profile_privileges()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT public.is_admin() THEN
        -- Non-admin cannot alter role_id, department_id, employee_code, or status
        IF NEW.role_id IS DISTINCT FROM OLD.role_id THEN
            RAISE EXCEPTION 'Only administrators can change profile roles';
        END IF;
        IF NEW.department_id IS DISTINCT FROM OLD.department_id THEN
            RAISE EXCEPTION 'Only administrators can change profile departments';
        END IF;
        IF NEW.status IS DISTINCT FROM OLD.status THEN
            RAISE EXCEPTION 'Only administrators can change profile status';
        END IF;
        IF NEW.employee_code IS DISTINCT FROM OLD.employee_code THEN
            RAISE EXCEPTION 'Employee code cannot be modified';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_protect_profile_privileges ON public.profiles;
CREATE TRIGGER trg_protect_profile_privileges
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.protect_profile_privileges();

-- ==============================================================================
-- 5. Cases Table Policies
-- ==============================================================================
DROP POLICY IF EXISTS "Select authorized cases" ON public.cases;
CREATE POLICY "Select authorized cases"
    ON public.cases FOR SELECT
    TO authenticated
    USING (public.can_access_case(id));

DROP POLICY IF EXISTS "Insert cases" ON public.cases;
CREATE POLICY "Insert cases"
    ON public.cases FOR INSERT
    TO authenticated
    WITH CHECK (
        created_by = auth.uid() 
        AND public.get_current_role_name() IN ('ADMIN', 'SUPERVISOR', 'INVESTIGATOR', 'OFFICER')
    );

DROP POLICY IF EXISTS "Update cases" ON public.cases;
CREATE POLICY "Update cases"
    ON public.cases FOR UPDATE
    TO authenticated
    USING (
        public.is_admin()
        OR created_by = auth.uid()
        OR assigned_to = auth.uid()
        OR (public.get_current_role_name() = 'SUPERVISOR' AND department_id = public.get_current_department_id())
    )
    WITH CHECK (
        public.is_admin()
        OR created_by = auth.uid()
        OR assigned_to = auth.uid()
        OR (public.get_current_role_name() = 'SUPERVISOR' AND department_id = public.get_current_department_id())
    );

DROP POLICY IF EXISTS "Delete cases" ON public.cases;
CREATE POLICY "Delete cases"
    ON public.cases FOR DELETE
    TO authenticated
    USING (public.is_admin());

-- ==============================================================================
-- 6. Documents Table Policies
-- ==============================================================================
DROP POLICY IF EXISTS "Select authorized documents" ON public.documents;
CREATE POLICY "Select authorized documents"
    ON public.documents FOR SELECT
    TO authenticated
    USING (public.can_access_document(id, 'view'));

DROP POLICY IF EXISTS "Insert documents" ON public.documents;
CREATE POLICY "Insert documents"
    ON public.documents FOR INSERT
    TO authenticated
    WITH CHECK (
        uploaded_by = auth.uid()
        AND public.get_current_role_name() IN ('ADMIN', 'SUPERVISOR', 'INVESTIGATOR', 'OFFICER')
        AND (case_id IS NULL OR public.can_access_case(case_id))
    );

DROP POLICY IF EXISTS "Update documents" ON public.documents;
CREATE POLICY "Update documents"
    ON public.documents FOR UPDATE
    TO authenticated
    USING (
        public.is_admin()
        OR uploaded_by = auth.uid()
        OR public.can_access_document(id, 'edit')
    )
    WITH CHECK (
        public.is_admin()
        OR uploaded_by = auth.uid()
        OR public.can_access_document(id, 'edit')
    );

DROP POLICY IF EXISTS "Delete documents" ON public.documents;
CREATE POLICY "Delete documents"
    ON public.documents FOR DELETE
    TO authenticated
    USING (public.is_admin());

-- ==============================================================================
-- 7. Document Versions Table Policies
-- ==============================================================================
DROP POLICY IF EXISTS "Select authorized document versions" ON public.document_versions;
CREATE POLICY "Select authorized document versions"
    ON public.document_versions FOR SELECT
    TO authenticated
    USING (public.can_access_document(document_id, 'view'));

DROP POLICY IF EXISTS "Insert document versions" ON public.document_versions;
CREATE POLICY "Insert document versions"
    ON public.document_versions FOR INSERT
    TO authenticated
    WITH CHECK (
        created_by = auth.uid()
        AND (
            public.is_admin()
            OR public.can_access_document(document_id, 'edit')
            OR EXISTS (SELECT 1 FROM public.documents d WHERE d.id = document_id AND d.uploaded_by = auth.uid())
        )
    );

-- Historical document versions are immutable: No UPDATE allowed
-- Only admin can delete versions if necessary under strict data compliance
DROP POLICY IF EXISTS "Admin delete document versions" ON public.document_versions;
CREATE POLICY "Admin delete document versions"
    ON public.document_versions FOR DELETE
    TO authenticated
    USING (public.is_admin());

-- ==============================================================================
-- 8. Case Documents Junction Table Policies
-- ==============================================================================
DROP POLICY IF EXISTS "Select case documents" ON public.case_documents;
CREATE POLICY "Select case documents"
    ON public.case_documents FOR SELECT
    TO authenticated
    USING (public.can_access_case(case_id));

DROP POLICY IF EXISTS "Insert case documents" ON public.case_documents;
CREATE POLICY "Insert case documents"
    ON public.case_documents FOR INSERT
    TO authenticated
    WITH CHECK (
        added_by = auth.uid()
        AND public.can_access_case(case_id)
        AND public.can_access_document(document_id, 'view')
    );

DROP POLICY IF EXISTS "Delete case documents" ON public.case_documents;
CREATE POLICY "Delete case documents"
    ON public.case_documents FOR DELETE
    TO authenticated
    USING (
        public.is_admin()
        OR added_by = auth.uid()
        OR public.can_access_case(case_id)
    );

-- ==============================================================================
-- 9. Evidence Table Policies
-- ==============================================================================
DROP POLICY IF EXISTS "Select case evidence" ON public.evidence;
CREATE POLICY "Select case evidence"
    ON public.evidence FOR SELECT
    TO authenticated
    USING (public.can_access_case(case_id));

DROP POLICY IF EXISTS "Insert evidence" ON public.evidence;
CREATE POLICY "Insert evidence"
    ON public.evidence FOR INSERT
    TO authenticated
    WITH CHECK (
        collected_by = auth.uid()
        AND public.can_access_case(case_id)
        AND public.get_current_role_name() IN ('ADMIN', 'SUPERVISOR', 'INVESTIGATOR', 'OFFICER')
    );

DROP POLICY IF EXISTS "Update evidence" ON public.evidence;
CREATE POLICY "Update evidence"
    ON public.evidence FOR UPDATE
    TO authenticated
    USING (
        public.is_admin()
        OR current_custodian = auth.uid()
        OR collected_by = auth.uid()
        OR EXISTS (SELECT 1 FROM public.cases c WHERE c.id = case_id AND c.assigned_to = auth.uid())
    )
    WITH CHECK (
        public.is_admin()
        OR current_custodian = auth.uid()
        OR collected_by = auth.uid()
        OR EXISTS (SELECT 1 FROM public.cases c WHERE c.id = case_id AND c.assigned_to = auth.uid())
    );

DROP POLICY IF EXISTS "Delete evidence" ON public.evidence;
CREATE POLICY "Delete evidence"
    ON public.evidence FOR DELETE
    TO authenticated
    USING (public.is_admin());

-- ==============================================================================
-- 10. Document Permissions Table Policies
-- ==============================================================================
DROP POLICY IF EXISTS "Select document permissions" ON public.document_permissions;
CREATE POLICY "Select document permissions"
    ON public.document_permissions FOR SELECT
    TO authenticated
    USING (
        profile_id = auth.uid()
        OR created_by = auth.uid()
        OR public.is_admin()
        OR EXISTS (SELECT 1 FROM public.documents d WHERE d.id = document_id AND d.uploaded_by = auth.uid())
    );

DROP POLICY IF EXISTS "Manage document permissions" ON public.document_permissions;
CREATE POLICY "Manage document permissions"
    ON public.document_permissions FOR ALL
    TO authenticated
    USING (
        public.is_admin()
        OR created_by = auth.uid()
        OR EXISTS (SELECT 1 FROM public.documents d WHERE d.id = document_id AND d.uploaded_by = auth.uid())
        OR public.can_access_document(document_id, 'share')
    )
    WITH CHECK (
        public.is_admin()
        OR created_by = auth.uid()
        OR EXISTS (SELECT 1 FROM public.documents d WHERE d.id = document_id AND d.uploaded_by = auth.uid())
        OR public.can_access_document(document_id, 'share')
    );

-- ==============================================================================
-- 11. Face Embeddings Table Policies
-- ==============================================================================
DROP POLICY IF EXISTS "View face embeddings" ON public.face_embeddings;
CREATE POLICY "View face embeddings"
    ON public.face_embeddings FOR SELECT
    TO authenticated
    USING (
        profile_id = auth.uid()
        OR public.is_admin()
    );

DROP POLICY IF EXISTS "Manage face embeddings" ON public.face_embeddings;
CREATE POLICY "Manage face embeddings"
    ON public.face_embeddings FOR ALL
    TO authenticated
    USING (
        profile_id = auth.uid()
        OR public.is_admin()
    )
    WITH CHECK (
        profile_id = auth.uid()
        OR public.is_admin()
    );

-- ==============================================================================
-- 12. Audit Logs Table Policies (Append-Only)
-- ==============================================================================
DROP POLICY IF EXISTS "Select audit logs" ON public.audit_logs;
CREATE POLICY "Select audit logs"
    ON public.audit_logs FOR SELECT
    TO authenticated
    USING (
        public.is_admin()
        OR public.get_current_role_name() = 'SUPERVISOR'
    );

DROP POLICY IF EXISTS "Insert audit logs" ON public.audit_logs;
CREATE POLICY "Insert audit logs"
    ON public.audit_logs FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- Explicitly NO UPDATE or DELETE policies on audit_logs: Guarantee tamper-proof audit trail

-- ==============================================================================
-- 13. Access Logs Table Policies
-- ==============================================================================
DROP POLICY IF EXISTS "Select access logs" ON public.access_logs;
CREATE POLICY "Select access logs"
    ON public.access_logs FOR SELECT
    TO authenticated
    USING (
        profile_id = auth.uid()
        OR public.is_admin()
    );

DROP POLICY IF EXISTS "Insert access logs" ON public.access_logs;
CREATE POLICY "Insert access logs"
    ON public.access_logs FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- Explicitly NO UPDATE or DELETE on access_logs

-- ==============================================================================
-- 14. Notifications Table Policies
-- ==============================================================================
DROP POLICY IF EXISTS "Users can view their notifications" ON public.notifications;
CREATE POLICY "Users can view their notifications"
    ON public.notifications FOR SELECT
    TO authenticated
    USING (profile_id = auth.uid());

DROP POLICY IF EXISTS "Users can update their notifications" ON public.notifications;
CREATE POLICY "Users can update their notifications"
    ON public.notifications FOR UPDATE
    TO authenticated
    USING (profile_id = auth.uid())
    WITH CHECK (profile_id = auth.uid());

DROP POLICY IF EXISTS "Users can delete their notifications" ON public.notifications;
CREATE POLICY "Users can delete their notifications"
    ON public.notifications FOR DELETE
    TO authenticated
    USING (profile_id = auth.uid());

DROP POLICY IF EXISTS "Insert notifications" ON public.notifications;
CREATE POLICY "Insert notifications"
    ON public.notifications FOR INSERT
    TO authenticated
    WITH CHECK (true);
