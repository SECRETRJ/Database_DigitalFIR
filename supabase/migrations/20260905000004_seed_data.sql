-- ==============================================================================
-- Secure Digital Document Management System — Seed Data Migration
-- Project: Secure Digital Document Management System for Legal & Investigation Documents
-- Migration: 20260905000004_seed_data.sql
-- ==============================================================================

-- 1. Seed Roles
INSERT INTO public.roles (id, name, description, permissions)
VALUES 
    (
        '00000000-0000-0000-0001-000000000001',
        'ADMIN',
        'Full administrative privileges over all departments, users, cases, documents, and audit trails',
        '{"all": true, "manage_users": true, "manage_departments": true, "view_all_cases": true, "manage_roles": true, "view_audit_logs": true}'::jsonb
    ),
    (
        '00000000-0000-0000-0001-000000000002',
        'INVESTIGATOR',
        'Primary investigator with rights to create, investigate, manage assigned cases, upload evidence and documents',
        '{"cases": ["create", "read_assigned", "update_assigned"], "documents": ["create", "read", "update_own", "version"], "evidence": ["create", "custody_transfer"]}'::jsonb
    ),
    (
        '00000000-0000-0000-0001-000000000003',
        'OFFICER',
        'Field officer authorized to record field reports, submit evidence, and view department cases',
        '{"cases": ["create", "read_department"], "documents": ["create", "read_department"], "evidence": ["create"]}'::jsonb
    ),
    (
        '00000000-0000-0000-0001-000000000004',
        'SUPERVISOR',
        'Unit or departmental supervisor with authority to review, assign, close cases and review audit logs',
        '{"cases": ["create", "read_department", "assign", "close"], "documents": ["read_department", "approve", "share"], "audit_logs": ["read_department"]}'::jsonb
    ),
    (
        '00000000-0000-0000-0001-000000000005',
        'VIEWER',
        'Read-only auditor or legal counsel with access only to explicitly permitted cases and documents',
        '{"cases": ["read_permitted"], "documents": ["read_permitted"]}'::jsonb
    )
ON CONFLICT (name) DO UPDATE SET 
    description = EXCLUDED.description,
    permissions = EXCLUDED.permissions;

-- 2. Seed Departments
INSERT INTO public.departments (id, name, code, status)
VALUES 
    ('00000000-0000-0000-0002-000000000001', 'Major Crimes Division', 'MCD', 'active'),
    ('00000000-0000-0000-0002-000000000002', 'Cyber Crime Unit', 'CCU', 'active'),
    ('00000000-0000-0000-0002-000000000003', 'Internal Affairs', 'IA', 'active'),
    ('00000000-0000-0000-0002-000000000004', 'Legal Directorate', 'LD', 'active'),
    ('00000000-0000-0000-0002-000000000005', 'Forensics & Evidence Branch', 'FEB', 'active')
ON CONFLICT (code) DO UPDATE SET 
    name = EXCLUDED.name,
    status = EXCLUDED.status;

-- 3. Seed Development Auth Users & Profiles
-- Password for demo accounts: "DevPassword123!"
DO $$
DECLARE
    v_enc_pw TEXT;
    v_admin_id UUID := '00000000-0000-0000-0003-000000000001';
    v_inv_id UUID   := '00000000-0000-0000-0003-000000000002';
    v_off_id UUID   := '00000000-0000-0000-0003-000000000003';
    v_sup_id UUID   := '00000000-0000-0000-0003-000000000004';
    v_view_id UUID  := '00000000-0000-0000-0003-000000000005';
BEGIN
    v_enc_pw := extensions.crypt('DevPassword123!', extensions.gen_salt('bf'));

    -- User 1: Admin
    INSERT INTO auth.users (
        id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data,
        confirmation_token, recovery_token, email_change_token_new, email_change,
        email_change_token_current, phone_change, phone_change_token, reauthentication_token,
        created_at, updated_at
    ) VALUES (
        v_admin_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'admin@legal-investigation.test', v_enc_pw, now(),
        '{"provider": "email", "providers": ["email"]}'::jsonb,
        '{"full_name": "Chief Insp. Sarah Connor", "employee_code": "EMP-ADMIN-001"}'::jsonb,
        '', '', '', '', '', '', '', '',
        now(), now()
    ) ON CONFLICT (id) DO UPDATE SET encrypted_password = v_enc_pw, confirmation_token = '';

    -- User 2: Investigator
    INSERT INTO auth.users (
        id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data,
        confirmation_token, recovery_token, email_change_token_new, email_change,
        email_change_token_current, phone_change, phone_change_token, reauthentication_token,
        created_at, updated_at
    ) VALUES (
        v_inv_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'investigator@legal-investigation.test', v_enc_pw, now(),
        '{"provider": "email", "providers": ["email"]}'::jsonb,
        '{"full_name": "Detective James Miller", "employee_code": "EMP-INV-002"}'::jsonb,
        '', '', '', '', '', '', '', '',
        now(), now()
    ) ON CONFLICT (id) DO UPDATE SET encrypted_password = v_enc_pw, confirmation_token = '';

    -- User 3: Officer
    INSERT INTO auth.users (
        id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data,
        confirmation_token, recovery_token, email_change_token_new, email_change,
        email_change_token_current, phone_change, phone_change_token, reauthentication_token,
        created_at, updated_at
    ) VALUES (
        v_off_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'officer@legal-investigation.test', v_enc_pw, now(),
        '{"provider": "email", "providers": ["email"]}'::jsonb,
        '{"full_name": "Officer Maya Lin", "employee_code": "EMP-OFF-003"}'::jsonb,
        '', '', '', '', '', '', '', '',
        now(), now()
    ) ON CONFLICT (id) DO UPDATE SET encrypted_password = v_enc_pw, confirmation_token = '';

    -- User 4: Supervisor
    INSERT INTO auth.users (
        id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data,
        confirmation_token, recovery_token, email_change_token_new, email_change,
        email_change_token_current, phone_change, phone_change_token, reauthentication_token,
        created_at, updated_at
    ) VALUES (
        v_sup_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'supervisor@legal-investigation.test', v_enc_pw, now(),
        '{"provider": "email", "providers": ["email"]}'::jsonb,
        '{"full_name": "Capt. Marcus Vance", "employee_code": "EMP-SUP-004"}'::jsonb,
        '', '', '', '', '', '', '', '',
        now(), now()
    ) ON CONFLICT (id) DO UPDATE SET encrypted_password = v_enc_pw, confirmation_token = '';

    -- User 5: Viewer
    INSERT INTO auth.users (
        id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data,
        confirmation_token, recovery_token, email_change_token_new, email_change,
        email_change_token_current, phone_change, phone_change_token, reauthentication_token,
        created_at, updated_at
    ) VALUES (
        v_view_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'viewer@legal-investigation.test', v_enc_pw, now(),
        '{"provider": "email", "providers": ["email"]}'::jsonb,
        '{"full_name": "Counsel Helena Rossi", "employee_code": "EMP-VIEW-005"}'::jsonb,
        '', '', '', '', '', '', '', '',
        now(), now()
    ) ON CONFLICT (id) DO UPDATE SET encrypted_password = v_enc_pw, confirmation_token = '';

    -- Profiles
    INSERT INTO public.profiles (id, employee_code, full_name, role_id, department_id, phone, status)
    VALUES 
        (v_admin_id, 'EMP-ADMIN-001', 'Chief Insp. Sarah Connor', '00000000-0000-0000-0001-000000000001', '00000000-0000-0000-0002-000000000001', '+1-555-0101', 'active'),
        (v_inv_id,   'EMP-INV-002',   'Detective James Miller',   '00000000-0000-0000-0001-000000000002', '00000000-0000-0000-0002-000000000002', '+1-555-0102', 'active'),
        (v_off_id,   'EMP-OFF-003',   'Officer Maya Lin',         '00000000-0000-0000-0001-000000000003', '00000000-0000-0000-0002-000000000002', '+1-555-0103', 'active'),
        (v_sup_id,   'EMP-SUP-004',   'Capt. Marcus Vance',       '00000000-0000-0000-0001-000000000004', '00000000-0000-0000-0002-000000000002', '+1-555-0104', 'active'),
        (v_view_id,  'EMP-VIEW-005',  'Counsel Helena Rossi',     '00000000-0000-0000-0001-000000000005', '00000000-0000-0000-0002-000000000004', '+1-555-0105', 'active')
    ON CONFLICT (id) DO UPDATE SET 
        full_name = EXCLUDED.full_name,
        role_id = EXCLUDED.role_id,
        department_id = EXCLUDED.department_id,
        status = EXCLUDED.status;
END $$;

-- 4. Seed Cases
INSERT INTO public.cases (
    id, case_number, title, description, case_type, status, priority, created_by, assigned_to, department_id
) VALUES 
    (
        '00000000-0000-0000-0004-000000000001',
        'CASE-2026-CCU-001',
        'Municipal Energy Grid Ransomware Intrusion',
        'Investigation into unauthorized penetration, credential harvesting, and ransom deployment across power grid SCADA telemetry.',
        'Cyber Crime / Critical Infrastructure',
        'open',
        'critical',
        '00000000-0000-0000-0003-000000000004', -- created by Supervisor Vance
        '00000000-0000-0000-0003-000000000002', -- assigned to Det. Miller
        '00000000-0000-0000-0002-000000000002'  -- Cyber Crime Unit
    ),
    (
        '00000000-0000-0000-0004-000000000002',
        'CASE-2026-MCD-042',
        'Metropolitan Commercial Bank Wire Fraud & Forfeiture',
        'Investigation of cross-border shell corporation fraudulent wire transfers totaling $4.8M.',
        'Financial Fraud',
        'under_review',
        'high',
        '00000000-0000-0000-0003-000000000001', -- created by Chief Connor
        '00000000-0000-0000-0003-000000000002', -- assigned to Det. Miller
        '00000000-0000-0000-0002-000000000001'  -- Major Crimes Division
    )
ON CONFLICT (case_number) DO UPDATE SET 
    title = EXCLUDED.title,
    status = EXCLUDED.status,
    priority = EXCLUDED.priority;

-- 5. Seed Documents
INSERT INTO public.documents (
    id, case_id, title, document_type, storage_bucket, storage_path, mime_type, file_size, checksum_sha256, classification, uploaded_by
) VALUES 
    (
        '00000000-0000-0000-0005-000000000001',
        '00000000-0000-0000-0004-000000000001',
        'Initial Incident First Information Report (FIR)',
        'FIR',
        'case-documents',
        'cases/00000000-0000-0000-0004-000000000001/documents/00000000-0000-0000-0005-000000000001/v1/FIR-CCU-001.pdf',
        'application/pdf',
        1048576,
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        'restricted',
        '00000000-0000-0000-0003-000000000002'
    ),
    (
        '00000000-0000-0000-0005-000000000002',
        '00000000-0000-0000-0004-000000000001',
        'Network Packet Capture & Forensic Analysis Report',
        'forensic_report',
        'case-documents',
        'cases/00000000-0000-0000-0004-000000000001/documents/00000000-0000-0000-0005-000000000002/v1/PCAP_Forensics.pdf',
        'application/pdf',
        5242880,
        '7d793037a0760186574b0282f2f435e7b1e5077469082f4f35f5a3f318a47368',
        'confidential',
        '00000000-0000-0000-0003-000000000002'
    ),
    (
        '00000000-0000-0000-0005-000000000003',
        '00000000-0000-0000-0004-000000000002',
        'Forensic Financial Audit Statement',
        'audit_statement',
        'case-documents',
        'cases/00000000-0000-0000-0004-000000000002/documents/00000000-0000-0000-0005-000000000003/v1/Financial_Audit.pdf',
        'application/pdf',
        2097152,
        'a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e',
        'confidential',
        '00000000-0000-0000-0003-000000000001'
    )
ON CONFLICT (id) DO NOTHING;

-- 6. Seed Case-Document Junction
INSERT INTO public.case_documents (case_id, document_id, relationship_type, added_by)
VALUES 
    ('00000000-0000-0000-0004-000000000001', '00000000-0000-0000-0005-000000000001', 'primary', '00000000-0000-0000-0003-000000000002'),
    ('00000000-0000-0000-0004-000000000001', '00000000-0000-0000-0005-000000000002', 'evidence', '00000000-0000-0000-0003-000000000002'),
    ('00000000-0000-0000-0004-000000000002', '00000000-0000-0000-0005-000000000003', 'primary', '00000000-0000-0000-0003-000000000001')
ON CONFLICT (case_id, document_id) DO NOTHING;

-- 7. Seed Evidence Items
INSERT INTO public.evidence (
    id, case_id, document_id, evidence_code, evidence_type, description, hash_sha256, collected_by, collected_at, current_custodian, status, storage_bucket, storage_path
) VALUES 
    (
        '00000000-0000-0000-0006-000000000001',
        '00000000-0000-0000-0004-000000000001',
        '00000000-0000-0000-0005-000000000002',
        'EVID-CCU-2026-001',
        'digital',
        'Bit-stream forensically authenticated dump of server node edge-scada-01',
        '4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',
        '00000000-0000-0000-0003-000000000002',
        now() - INTERVAL '2 days',
        '00000000-0000-0000-0003-000000000002',
        'stored',
        'evidence-files',
        'cases/00000000-0000-0000-0004-000000000001/evidence/00000000-0000-0000-0006-000000000001/scada_dump.dd.gz'
    ),
    (
        '00000000-0000-0000-0006-000000000002',
        '00000000-0000-0000-0004-000000000002',
        NULL,
        'EVID-MCD-2026-015',
        'device',
        'Hardware cryptographic token seized during premises search warrant execution',
        '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
        '00000000-0000-0000-0003-000000000003',
        now() - INTERVAL '1 day',
        '00000000-0000-0000-0003-000000000001',
        'transferred',
        NULL,
        NULL
    )
ON CONFLICT (evidence_code) DO NOTHING;

-- 8. Seed Document Permissions
-- Grant legal counsel viewer explicit view permission on FIR
INSERT INTO public.document_permissions (
    id, document_id, profile_id, role_id, can_view, can_download, can_edit, can_share, created_by
) VALUES 
    (
        '00000000-0000-0000-0007-000000000001',
        '00000000-0000-0000-0005-000000000001',
        '00000000-0000-0000-0003-000000000005', -- Counsel Helena Rossi
        NULL,
        true,
        true,
        false,
        false,
        '00000000-0000-0000-0003-000000000002'  -- Det. Miller
    )
ON CONFLICT (document_id, profile_id) DO NOTHING;

-- 9. Seed Biometric Face Embedding (512-dim demo vector)
DO $$
DECLARE
    v_vec TEXT;
BEGIN
    -- Construct a deterministic 512-dimensional vector with normalized coordinates
    SELECT '[' || string_agg(round((sin(i * 0.05) / 10.0)::numeric, 4)::text, ',') || ']'
    INTO v_vec
    FROM generate_series(1, 512) AS i;

    INSERT INTO public.face_embeddings (
        id, profile_id, embedding, model_version, status
    ) VALUES (
        '00000000-0000-0000-0008-000000000001',
        '00000000-0000-0000-0003-000000000002', -- Det. James Miller
        v_vec::extensions.vector,
        'ArcFace-r100-v1',
        'active'
    ) ON CONFLICT (id) DO NOTHING;
END $$;

-- 10. Seed Initial Audit Logs & Access Logs
INSERT INTO public.audit_logs (
    actor_id, action, entity_type, entity_id, case_id, details
) VALUES 
    (
        '00000000-0000-0000-0003-000000000004',
        'CASE_CREATE',
        'case',
        '00000000-0000-0000-0004-000000000001',
        '00000000-0000-0000-0004-000000000001',
        '{"case_number": "CASE-2026-CCU-001", "classification": "critical"}'::jsonb
    ),
    (
        '00000000-0000-0000-0003-000000000002',
        'DOCUMENT_UPLOAD',
        'document',
        '00000000-0000-0000-0005-000000000001',
        '00000000-0000-0000-0004-000000000001',
        '{"title": "Initial Incident First Information Report (FIR)", "checksum_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}'::jsonb
    );

INSERT INTO public.access_logs (
    profile_id, event_type, ip_address, device_info
) VALUES 
    (
        '00000000-0000-0000-0003-000000000001',
        'LOGIN_SUCCESS',
        '10.0.1.5'::inet,
        'SecOps Workstation 01 (Windows 11 Enterprise)'
    ),
    (
        '00000000-0000-0000-0003-000000000002',
        'FACE_AUTH_SUCCESS',
        '10.0.2.14'::inet,
        'Investigation Unit Terminal B (ArcFace biometric scanner)'
    );

-- 11. Seed Notifications
INSERT INTO public.notifications (
    profile_id, case_id, document_id, title, message, is_read
) VALUES 
    (
        '00000000-0000-0000-0003-000000000002',
        '00000000-0000-0000-0004-000000000001',
        NULL,
        'New Case Assigned',
        'You have been assigned as lead investigator on CASE-2026-CCU-001.',
        false
    ),
    (
        '00000000-0000-0000-0003-000000000005',
        '00000000-0000-0000-0004-000000000001',
        '00000000-0000-0000-0005-000000000001',
        'Document Access Granted',
        'You were granted view/download permissions on FIR-CCU-001 by Det. Miller.',
        false
    );
