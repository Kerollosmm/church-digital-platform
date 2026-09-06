import { spawnSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const testsDir = path.join(__dirname, '..', 'supabase', 'tests');
const files = fs.readdirSync(testsDir)
  .filter(f => f.endsWith('.sql') && f !== 'run_all.sql')
  .sort();

let passed = 0;
let failed = 0;
const failedSuites = [];

for (const file of files) {
  const filePath = path.join(testsDir, file);
  const sqlContent = fs.readFileSync(filePath);

  process.stdout.write(`• ${file.padEnd(45, ' ')} : `);

  // Pipe directly to psql inside container
  const res = spawnSync('docker', ['exec', '-i', 'supabase_db_church', 'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '--no-psqlrc'], {
    input: sqlContent,
    encoding: 'utf-8',
    maxBuffer: 10 * 1024 * 1024
  });

  const output = (res.stdout || '') + '\n' + (res.stderr || '');
  
  // Check for pgTAP failure markers or syntax/execution error
  const hasTapFailure = /not ok/i.test(output) || /# Looks like you failed/i.test(output);
  const hasPsqlError = res.status !== 0 || /ERROR:/i.test(output);

  if (hasTapFailure || hasPsqlError) {
    const reason = hasTapFailure ? 'FAIL (TAP Assertion)' : 'FAIL (Postgres Error)';
    console.log(`\x1b[31m${reason}\x1b[0m`);
    failed++;
    failedSuites.push({ file, reason, output: output.slice(0, 500) });
  } else {
    console.log(`\x1b[32mPASS\x1b[0m`);
    passed++;
  }
}

console.log(`\n======================================================`);
console.log(`TOTAL SUITES: ${files.length} | PASSED: ${passed} | FAILED: ${failed}`);
console.log(`======================================================\n`);

if (failed > 0) {
  console.error(`\x1b[31mFAILING SUITES (${failed}):\x1b[0m`);
  for (const f of failedSuites) {
    console.error(`  - ${f.file} (${f.reason})`);
  }
  process.exit(1);
} else {
  console.log(`\x1b[32mAll ${passed} SQL suites passed with verified TAP output!\x1b[0m\n`);
  process.exit(0);
}
