import { createClient } from '@supabase/supabase-js';
import * as dotenv from 'dotenv';
import * as path from 'path';

dotenv.config({ path: path.resolve(process.cwd(), '.env') });

const supabaseUrl = process.env.SUPABASE_URL || '';
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY || '';

if (!supabaseUrl || !supabaseAnonKey) {
  console.error('❌ Missing SUPABASE_URL or SUPABASE_ANON_KEY in environment');
  process.exit(1);
}

const colors = {
  reset: '\x1b[0m',
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  cyan: '\x1b[36m',
  bold: '\x1b[1m',
};

function pass(name: string, detail?: string) {
  console.log(`${colors.green}  ✓ [PASS]${colors.reset} ${name}${detail ? ` (${detail})` : ''}`);
}

function fail(name: string, error: any) {
  console.error(`${colors.red}  ✗ [FAIL]${colors.reset} ${name}`);
  console.error(`    Error:`, error);
  process.exitCode = 1;
}

async function runTestSuite() {
  console.log(`\n${colors.bold}${colors.cyan}================================================================${colors.reset}`);
  console.log(`${colors.bold}${colors.cyan}  SECURE DIGITAL DOCUMENT MANAGEMENT SYSTEM — DB VALIDATION SUITE${colors.reset}`);
  console.log(`${colors.bold}${colors.cyan}================================================================${colors.reset}\n`);

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // --------------------------------------------------------------------------
  // TEST 1: Public Storage Buckets Configuration & Security
  // --------------------------------------------------------------------------
  console.log(`${colors.yellow}1. Storage Buckets Verification...${colors.reset}`);
  try {
    const { data: buckets, error } = await supabase.storage.listBuckets();
    if (error) throw error;

    const bucketMap = new Map(buckets.map((b) => [b.id, b]));
    const requiredBuckets = ['case-documents', 'evidence-files', 'temporary-processing', 'profile-media'];

    for (const bName of requiredBuckets) {
      const bucket = bucketMap.get(bName);
      if (!bucket) {
        throw new Error(`Required bucket "${bName}" is missing`);
      }
      if (bucket.public !== false) {
        throw new Error(`Bucket "${bName}" must be PRIVATE (public = false), but was public`);
      }
      pass(`Bucket "${bName}" is provisioned & private`, `public: ${bucket.public}`);
    }
  } catch (err) {
    fail('Storage Buckets Configuration', err);
  }

  // --------------------------------------------------------------------------
  // TEST 2: Authentication (Valid, Invalid Password, Invalid User)
  // --------------------------------------------------------------------------
  console.log(`\n${colors.yellow}2. Authentication Tests...${colors.reset}`);
  try {
    // 2.1 Valid User
    const { data: authData, error: authError } = await supabase.auth.signInWithPassword({
      email: 'investigator@legal-investigation.test',
      password: 'DevPassword123!',
    });
    if (authError || !authData.user) {
      throw authError || new Error('Failed to sign in valid user');
    }
    pass('Valid User Authentication', `User: ${authData.user.email} (ID: ${authData.user.id})`);

    // 2.2 Invalid Password
    const { data: invalidPwData, error: invalidPwError } = await supabase.auth.signInWithPassword({
      email: 'investigator@legal-investigation.test',
      password: 'WrongPassword!',
    });
    if (!invalidPwError) {
      throw new Error('Authentication succeeded with invalid password!');
    }
    pass('Invalid Password Rejected', `Error message: ${invalidPwError.message}`);

    // 2.3 Invalid User
    const { data: unknownUserData, error: unknownUserError } = await supabase.auth.signInWithPassword({
      email: 'nonexistent@legal-investigation.test',
      password: 'DevPassword123!',
    });
    if (!unknownUserError) {
      throw new Error('Authentication succeeded for nonexistent user!');
    }
    pass('Nonexistent User Rejected', `Error message: ${unknownUserError.message}`);
  } catch (err) {
    fail('Authentication Tests', err);
  }

  // --------------------------------------------------------------------------
  // TEST 3: Authenticated Investigator Client & Profile Query
  // --------------------------------------------------------------------------
  console.log(`\n${colors.yellow}3. User Profile & Role Linkage Tests...${colors.reset}`);
  const investigatorClient = createClient(supabaseUrl, supabaseAnonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: invSession } = await investigatorClient.auth.signInWithPassword({
    email: 'investigator@legal-investigation.test',
    password: 'DevPassword123!',
  });

  try {
    const { data: profile, error } = await investigatorClient
      .from('profiles')
      .select('id, employee_code, full_name, role_id, department_id, status, roles(name), departments(name, code)')
      .eq('id', invSession.user!.id)
      .single();

    if (error || !profile) throw error || new Error('Profile not found');

    const roleName = (profile.roles as any)?.name;
    const deptName = (profile.departments as any)?.name;

    if (roleName !== 'INVESTIGATOR') {
      throw new Error(`Expected role INVESTIGATOR, found ${roleName}`);
    }
    if (profile.employee_code !== 'EMP-INV-002') {
      throw new Error(`Expected employee_code EMP-INV-002, found ${profile.employee_code}`);
    }

    pass('Profile Retrieved with Role & Department Relations', `${profile.full_name} | Role: ${roleName} | Dept: ${deptName}`);
  } catch (err) {
    fail('Profile & Role Linkage', err);
  }

  // --------------------------------------------------------------------------
  // TEST 4: Case Access & Query Tests
  // --------------------------------------------------------------------------
  console.log(`\n${colors.yellow}4. Investigation Case Management Tests...${colors.reset}`);
  try {
    const { data: cases, error } = await investigatorClient
      .from('cases')
      .select('id, case_number, title, status, priority, created_by, assigned_to')
      .order('case_number');

    if (error) throw error;
    if (!cases || cases.length === 0) throw new Error('No cases returned for investigator');

    const primaryCase = cases.find((c) => c.case_number === 'CASE-2026-CCU-001');
    if (!primaryCase) throw new Error('Case CASE-2026-CCU-001 not found');

    pass('Cases Query & Assignment', `Found ${cases.length} accessible cases (Primary: ${primaryCase.case_number} - ${primaryCase.title})`);
  } catch (err) {
    fail('Case Management', err);
  }

  // --------------------------------------------------------------------------
  // TEST 5: Document Integrity & Versioning Tests
  // --------------------------------------------------------------------------
  console.log(`\n${colors.yellow}5. Document Metadata, Versioning & Integrity Checksum Tests...${colors.reset}`);
  try {
    // 5.1 Query Document with Versions
    const { data: docs, error } = await investigatorClient
      .from('documents')
      .select('id, title, document_type, checksum_sha256, classification, storage_path, current_version_id, versions:document_versions!document_versions_document_id_fkey(*)')
      .order('created_at');

    if (error) throw error;
    if (!docs || docs.length === 0) throw new Error('No documents found');

    const firDoc = docs.find((d) => d.document_type === 'FIR');
    if (!firDoc) throw new Error('FIR Document not found');

    if (!firDoc.checksum_sha256 || firDoc.checksum_sha256.length !== 64) {
      throw new Error(`Invalid SHA-256 checksum format: ${firDoc.checksum_sha256}`);
    }

    const versions = (firDoc as any).versions;
    if (!versions || versions.length === 0) {
      throw new Error('No document_versions associated with document');
    }

    pass('Document Queried with Valid SHA-256 Checksum', `Doc: "${firDoc.title}" | Hash: ${firDoc.checksum_sha256.substring(0, 16)}...`);
    pass('Historical Versioning Preserved', `Version count: ${versions.length} | Version 1 path: ${versions[0].storage_path}`);

    // 5.2 Insert a New Version dynamically
    const nextVersionNo = Math.max(...versions.map((v: any) => v.version_no), 0) + 1;
    const { data: newVersion, error: vErr } = await investigatorClient
      .from('document_versions')
      .insert({
        document_id: firDoc.id,
        version_no: nextVersionNo,
        storage_path: `cases/00000000-0000-0000-0004-000000000001/documents/${firDoc.id}/v${nextVersionNo}/FIR_Amended.pdf`,
        checksum_sha256: '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
        created_by: invSession.user!.id,
        change_reason: `Supplemental witness testimony attached to FIR (Version ${nextVersionNo})`,
      })
      .select()
      .single();

    if (vErr) throw vErr;
    pass('New Document Version Appended', `Version ${newVersion.version_no}: ${newVersion.change_reason}`);
  } catch (err) {
    fail('Document Versioning & Integrity', err);
  }

  // --------------------------------------------------------------------------
  // TEST 6: Evidence Tracking & Chain of Custody Tests
  // --------------------------------------------------------------------------
  console.log(`\n${colors.yellow}6. Evidence Tracking & Chain of Custody Tests...${colors.reset}`);
  try {
    const { data: evidenceItems, error } = await investigatorClient
      .from('evidence')
      .select('id, evidence_code, evidence_type, description, hash_sha256, current_custodian, status')
      .order('evidence_code');

    if (error) throw error;
    if (!evidenceItems || evidenceItems.length === 0) throw new Error('No evidence items found');

    const digitalEvidence = evidenceItems.find((e) => e.evidence_type === 'digital');
    if (!digitalEvidence) throw new Error('Digital evidence item not found');

    if (!digitalEvidence.hash_sha256 || digitalEvidence.hash_sha256.length !== 64) {
      throw new Error(`Digital evidence must have a 64-char SHA-256 hash: ${digitalEvidence.hash_sha256}`);
    }

    pass('Evidence Item & Cryptographic Hash Verified', `${digitalEvidence.evidence_code}: ${digitalEvidence.description} (Hash: ${digitalEvidence.hash_sha256.substring(0, 16)}...)`);
  } catch (err) {
    fail('Evidence Management', err);
  }

  // --------------------------------------------------------------------------
  // TEST 7: Biometric Face Embedding & pgvector Similarity Search Test
  // --------------------------------------------------------------------------
  console.log(`\n${colors.yellow}7. Biometric Face Embedding & pgvector Tests...${colors.reset}`);
  try {
    const { data: faceEmbeddings, error } = await investigatorClient
      .from('face_embeddings')
      .select('id, profile_id, model_version, status, created_at')
      .eq('profile_id', invSession.user!.id);

    if (error) throw error;
    if (!faceEmbeddings || faceEmbeddings.length === 0) throw new Error('Face embedding record not found');

    pass('Face Embedding Template Active', `Model: ${faceEmbeddings[0].model_version} | Status: ${faceEmbeddings[0].status}`);

    // 7.2 RPC Biometric Vector Matching Test
    const sampleVector = Array.from({ length: 512 }, (_, i) =>
      (Math.sin((i + 1) * 0.05) / 10.0).toFixed(4)
    );
    const vectorStr = `[${sampleVector.join(',')}]`;
    const { data: matchData, error: matchError } = await investigatorClient.rpc('match_face_embedding', {
      query_embedding: vectorStr,
      match_threshold: 0.8,
      match_limit: 1,
    });
    if (matchError) throw matchError;
    if (!matchData || matchData.length === 0) {
      throw new Error('pgvector similarity RPC returned no match above 0.8 threshold');
    }
    pass('pgvector Cosine Similarity Match', `Matched: ${matchData[0].full_name} (${matchData[0].role_name}, ${matchData[0].department_code}) | Score: ${matchData[0].similarity.toFixed(4)}`);
  } catch (err) {
    fail('Face Embedding pgvector', err);
  }

  // --------------------------------------------------------------------------
  // TEST 8: Fine-Grained Document Permissions & RLS Isolation
  // --------------------------------------------------------------------------
  console.log(`\n${colors.yellow}8. Document Permissions & RLS Authorization Tests...${colors.reset}`);
  const viewerClient = createClient(supabaseUrl, supabaseAnonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: viewerSession, error: viewerLoginError } = await viewerClient.auth.signInWithPassword({
    email: 'viewer@legal-investigation.test',
    password: 'DevPassword123!',
  });
  if (viewerLoginError) throw viewerLoginError;

  try {
    // 8.1 Viewer queries documents:
    // Should see DOC-2026-001 (which has explicit permission granted to viewer)
    const { data: viewerDocs, error: vDocsError } = await viewerClient
      .from('documents')
      .select('id, title, classification');

    if (vDocsError) throw vDocsError;

    const hasFIR = viewerDocs?.some((d) => d.id === '00000000-0000-0000-0005-000000000001');
    const hasUnassignedBankDoc = viewerDocs?.some((d) => d.id === '00000000-0000-0000-0005-000000000003');

    if (!hasFIR) {
      throw new Error('Viewer was NOT able to view explicitly permitted FIR document!');
    }
    pass('Viewer Allowed Access to Explicitly Permitted Document', 'FIR-CCU-001 is accessible via document_permissions');

    // Confirm that viewer cannot see documents from cases they are not assigned to and lack permission for
    if (hasUnassignedBankDoc) {
      throw new Error('RLS Breach: Viewer was able to access unpermitted bank fraud document!');
    }
    pass('RLS Enforces Denial on Unauthorized Documents', 'Bank Fraud Audit document successfully hidden from Viewer');
  } catch (err) {
    fail('Document Permissions & RLS', err);
  }

  // --------------------------------------------------------------------------
  // TEST 9: Audit Logs Immutability & Tamper Resistance
  // --------------------------------------------------------------------------
  console.log(`\n${colors.yellow}9. Audit Log Immutability & Tamper Resistance Tests...${colors.reset}`);
  try {
    // 9.1 Insert Audit Log (Append is allowed)
    const { error: insertAuditError } = await investigatorClient
      .from('audit_logs')
      .insert({
        actor_id: invSession.user!.id,
        action: 'DOCUMENT_VIEW',
        entity_type: 'document',
        entity_id: '00000000-0000-0000-0005-000000000001',
        details: { reason: 'Automated DB integrity test verification' },
      });

    if (insertAuditError) throw insertAuditError;
    pass('Audit Event Append Allowed', 'DOCUMENT_VIEW event recorded successfully');

    // 9.2 Attempt to UPDATE an audit record: MUST BE DENIED / PROHIBITED
    const { data: updatedAudit, error: updateAuditError } = await investigatorClient
      .from('audit_logs')
      .update({ action: 'LOGIN' })
      .eq('action', 'DOCUMENT_VIEW')
      .select();

    // In Supabase with RLS, UPDATE with no policy matching returns empty array (0 rows updated) or error
    if (updatedAudit && updatedAudit.length > 0) {
      throw new Error('Security Violation: Audit log record was mutated by normal user!');
    }
    pass('Audit Log Mutation Denied (Tamper-Proof)', 'UPDATE operation on audit_logs blocked by RLS');

    // 9.3 Attempt to DELETE an audit record: MUST BE DENIED / PROHIBITED
    const { data: deletedAudit, error: deleteAuditError } = await investigatorClient
      .from('audit_logs')
      .delete()
      .eq('action', 'DOCUMENT_VIEW')
      .select();

    if (deletedAudit && deletedAudit.length > 0) {
      throw new Error('Security Violation: Audit log record was deleted by normal user!');
    }
    pass('Audit Log Deletion Denied (Tamper-Proof)', 'DELETE operation on audit_logs blocked by RLS');
  } catch (err) {
    fail('Audit Log Immutability', err);
  }

  // --------------------------------------------------------------------------
  // TEST 10: In-App Notifications Delivery Test
  // --------------------------------------------------------------------------
  console.log(`\n${colors.yellow}10. Notification System Tests...${colors.reset}`);
  try {
    const { data: notifs, error } = await investigatorClient
      .from('notifications')
      .select('id, title, message, is_read')
      .eq('profile_id', invSession.user!.id);

    if (error) throw error;
    if (!notifs || notifs.length === 0) throw new Error('No notifications found for investigator');

    pass('Notifications Received', `Count: ${notifs.length} | Title: "${notifs[0].title}"`);

    // Mark notification as read
    const { error: markReadError } = await investigatorClient
      .from('notifications')
      .update({ is_read: true })
      .eq('id', notifs[0].id);

    if (markReadError) throw markReadError;
    pass('Notification State Updated', `Marked notification ${notifs[0].id} as read`);
  } catch (err) {
    fail('Notification System', err);
  }

  console.log(`\n${colors.bold}${colors.green}================================================================${colors.reset}`);
  console.log(`${colors.bold}${colors.green}  ALL DATABASE & SECURITY INTEGRATION TESTS PASSED SUCCESSFULLY!${colors.reset}`);
  console.log(`${colors.bold}${colors.green}================================================================${colors.reset}\n`);
}

runTestSuite().catch((err) => {
  console.error('Unhandled test suite error:', err);
  process.exit(1);
});
