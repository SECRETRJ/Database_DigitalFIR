# Secure Digital Document Management System — Database Layer

> **Production-Grade Supabase Architecture for Legal & Investigation Documents, Cases, Chain-of-Custody Evidence, Biometric Auth, and Audit Trails.**

---

## 1. Architecture Overview

- **Primary Database**: Supabase PostgreSQL 17 (Unified single database for all structured metadata, relationships, and audit trails).
- **Authentication**: Supabase Auth (Identity, sessions, JWTs, password authentication).
- **File Storage**: Supabase Storage (Private encrypted buckets for sensitive legal/case documents and evidence).
- **Security Enforcement**: PostgreSQL Row-Level Security (RLS) enabled on **all 13 application tables** and **storage.objects**.
- **Biometric Face Search**: PostgreSQL `pgvector` extension (512-dimensional face embeddings using ArcFace/FaceNet model vectors with HNSW cosine similarity index and dedicated RPC `match_face_embedding`).
- **Data Integrity**: Cryptographic SHA-256 checksums recorded for documents, versions, and digital evidence.

---

## 2. Core Tables (13 Tables)

| # | Table | Purpose | Primary Relationships & Keys |
|---|-------|---------|------------------------------|
| 1 | `roles` | System roles & permissions map | Primary: `id`. Roles: `ADMIN`, `INVESTIGATOR`, `OFFICER`, `SUPERVISOR`, `VIEWER`. |
| 2 | `departments` | Law enforcement & legal divisions | Primary: `id`. Referenced by `profiles` and `cases`. |
| 3 | `profiles` | User profiles & employment metadata | Primary: `id` (references `auth.users.id` ON DELETE CASCADE). FKs to `roles`, `departments`. |
| 4 | `cases` | Investigation case master records | Primary: `id`. FKs: `created_by`, `assigned_to` (`profiles`), `department_id` (`departments`). |
| 5 | `documents` | Master document metadata & storage pointers | Primary: `id`. FKs: `case_id` (`cases`), `uploaded_by` (`profiles`), `current_version_id` (`document_versions`). |
| 6 | `document_versions` | Immutable historical version records | Primary: `id`. FKs: `document_id` (`documents`), `created_by` (`profiles`). Unique `(document_id, version_no)`. |
| 7 | `case_documents` | Many-to-many case/document junction | Primary: `(case_id, document_id)`. FKs: `case_id`, `document_id`, `added_by`. |
| 8 | `evidence` | Physical & digital evidence with chain of custody | Primary: `id`. FKs: `case_id`, `document_id`, `collected_by`, `current_custodian`. SHA-256 checksum verified. |
| 9 | `document_permissions` | Fine-grained document access control | Primary: `id`. Targets either `profile_id` OR `role_id`. Flags: `can_view`, `can_download`, `can_edit`, `can_share`, `expires_at`. |
| 10 | `face_embeddings` | 512-dim biometric face templates | Primary: `id`. FK: `profile_id` (`profiles`). pgvector cosine distance index with HNSW. |
| 11 | `audit_logs` | Tamper-proof append-only security audit trail | Primary: `id`. FKs: `actor_id` (`profiles`), `case_id`. Prohibited from UPDATE/DELETE by RLS. |
| 12 | `access_logs` | Authentication & session history | Primary: `id`. Tracks `LOGIN_SUCCESS`, `LOGIN_FAILED`, `FACE_AUTH_SUCCESS`, etc. |
| 13 | `notifications` | In-app alerts & task assignments | Primary: `id`. FKs: `profile_id`, `case_id`, `document_id`. |

---

## 3. Storage Buckets Architecture

All buckets are configured as **PRIVATE** (`public = false`):

1. `case-documents` (Max 500 MB): Investigation reports, FIRs, court orders, charge sheets.
   - Path pattern: `cases/{case_id}/documents/{document_id}/{version}/filename`
2. `evidence-files` (Max 1 GB): Digital forensic disk dumps, CCTV footage, wiretaps, photos.
   - Path pattern: `cases/{case_id}/evidence/{evidence_id}/filename`
3. `temporary-processing` (Max 100 MB): User-isolated staging area for virus scans, OCR parsing, and chunking.
   - Path pattern: `{user_id}/{upload_batch}/{filename}`
4. `profile-media` (Max 10 MB): Officer badge photos and identification media.
   - Restricted to `image/jpeg`, `image/png`, `image/webp`.

---

## 4. Security & Access Control Model

### Role Hierarchy & Capabilities:
- **ADMIN**: Full management across departments, roles, cases, documents, and system audit logs.
- **SUPERVISOR**: Can review, assign, approve, and close cases and documents within their department.
- **INVESTIGATOR**: Full operational access to assigned cases, evidence creation, document uploads, and versioning.
- **OFFICER**: Field reporting, evidence collection, and department case browsing.
- **VIEWER**: Strict read-only access limited strictly to explicitly shared documents via `document_permissions`.

### Document Classification:
- `public`: Accessible to all authenticated personnel.
- `internal`: Internal law enforcement staff.
- `confidential`: Requires case assignment, department match, or explicit permission.
- `restricted`: Restricts editing and downloads to case team and supervisors.
- `highly_restricted`: Strict explicit document permission or Administrator role only.

---

## 5. Biometric Face Match Flow

```text
[Face Camera] 
    │
    ▼
[Face Recognition Model] ──(Generates 512-d float array)
    │
    ▼
[Supabase RPC: match_face_embedding]
    │  (HNSW Cosine Similarity search over face_embeddings table)
    ▼
[Match Profile Identified] (e.g. Detective James Miller, EMP-INV-002)
    │
    ▼
[Supabase Auth signInWithPassword] (Validates credentials against auth.users)
    │
    ▼
[Profile & Roles Loaded from Database] (Server-authoritative, never trusted from client)
```

---

## 6. Development & Testing

### Environment Setup
Ensure `.env` contains the required keys:
```bash
SUPABASE_URL=https://<your-project-id>.supabase.co
SUPABASE_ANON_KEY=<your-anon-key>
SUPABASE_PUBLISHABLE_KEY=<your-publishable-key>
```

### Commands
```bash
# Type check database client and schema definitions
npm run type-check

# Compile TypeScript to dist/
npm run build

# Run automated end-to-end integration test suite
npm run test:db
```
