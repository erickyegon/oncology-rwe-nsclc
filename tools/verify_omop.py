"""Compare OMOP CDM row counts with the filtered Synthea CSVs they were loaded from.
Usage (from the repository root): python tools/verify_omop.py <filtered_csv_dir>
Reads PG_* and PSQL_BIN from .Renviron. Exits non-zero if a hard check fails.
"""
import csv, os, re, subprocess, sys, shutil
csv.field_size_limit(1 << 24)
d = sys.argv[1].replace(chr(92), '/').rstrip('/') + '/'
env = dict(os.environ)
for line in open('.Renviron', encoding='utf-8'):
    if '=' in line and not line.lstrip().startswith('#'):
        k, v = line.rstrip('\r\n').split('=', 1); env[k] = v
env['PGPASSWORD'] = env['PG_PASSWORD']
PSQL = env.get('PSQL_BIN') or shutil.which('psql') or r'C:\Program Files\PostgreSQL\17\bin\psql.exe'
def q(sql):
    r = subprocess.run([PSQL, '-h', env['PG_HOST'], '-p', env['PG_PORT'], '-U', env['PG_USER'], '-d', env['PG_DB'], '-tA', '-c', sql],
                       capture_output=True, text=True, env=env)
    if r.returncode: raise SystemExit(r.stderr)
    return r.stdout.strip()
def rows(fn): return csv.DictReader(open(d + fn, encoding='utf-8', newline=''))
fails = []
def check(name, expected, actual, hard=True):
    ok = expected == actual
    print(f'{"OK  " if ok else ("FAIL" if hard else "note")}  {name}: source {expected:,} | OMOP {actual:,}')
    if not ok and hard: fails.append(name)

pat = list(rows('patients.csv'))
check('persons (patients.csv rows)', len(pat), int(q('select count(*) from cdm.person')))
check('deaths (patients with DEATHDATE)', sum(1 for r in pat if r['DEATHDATE']), int(q('select count(*) from cdm.death')))
check('observation periods', len(pat), int(q('select count(*) from cdm.observation_period')))

lc = re.compile(r'lung', re.I); ok_ = re.compile(r'cancer|carcinoma|neoplasm', re.I)
src_lc, codes, nsclc_p, staged_p = 0, set(), set(), set()
for r in rows('conditions.csv'):
    s = r['DESCRIPTION']
    if lc.search(s) and ok_.search(s) and 'uspected' not in s:
        src_lc += 1; codes.add(r['CODE'])
    if 'Non-small cell' in s:
        nsclc_p.add(r['PATIENT'])
        if 'TNM stage' in s: staged_p.add(r['PATIENT'])
incl = ",".join("'%s'" % c for c in sorted(codes))
check('lung cancer condition events (distinct person/date/source code)', src_lc,
      int(q(f"select count(*) from (select distinct person_id, condition_start_date, condition_source_value from cdm.condition_occurrence where condition_source_value in ({incl})) x")))
omop_rows = int(q(f"select count(*) from cdm.condition_occurrence where condition_source_value in ({incl})"))
print(f'note  lung cancer condition_occurrence rows: source {src_lc:,} | OMOP {omop_rows:,} (fan-out {omop_rows - src_lc:,}: a source code that maps to more than one Condition concept is written once per concept)')
for line in q(f"select condition_source_value, count(*) rows, count(distinct (person_id, condition_start_date)) events from cdm.condition_occurrence where condition_source_value in ({incl}) group by 1 having count(*) > count(distinct (person_id, condition_start_date)) order by 1").split(chr(10)):
    if line: print('      fan-out source code | rows | distinct events:', line)
print('      persons carrying standard concept 4110591 (Small cell carcinoma of lung):', q("select count(distinct person_id) from cdm.condition_occurrence where condition_concept_id=4110591"),
      '| of which stage-III NSCLC by source code 422968005:', q("select count(distinct person_id) from cdm.condition_occurrence where condition_concept_id=4110591 and condition_source_value='422968005'"))
print('      lung cancer source codes:', sorted(codes))
check('persons with an NSCLC condition', len(nsclc_p),
      int(q("select count(distinct p.person_source_value) from cdm.condition_occurrence c join cdm.person p using (person_id) where c.condition_source_value='254637007'")))
stage_codes = sorted({r['CODE'] for r in rows('conditions.csv') if 'Non-small cell' in r['DESCRIPTION'] and 'TNM stage' in r['DESCRIPTION']})
check('persons with an NSCLC TNM stage condition', len(staged_p),
      int(q("select count(distinct person_id) from cdm.condition_occurrence where condition_source_value in (%s)" % ",".join("'%s'" % c for c in stage_codes))))
print('      unmapped (concept_id = 0) among lung cancer rows:',
      q(f"select count(*) from cdm.condition_occurrence where condition_source_value in ({incl}) and condition_concept_id=0"))

print('\nTable counts (source rows -> OMOP rows; OMOP can differ because of visit consolidation and unmapped codes)')
def n(fn): return sum(1 for _ in rows(fn))
for src, tbl in (('encounters.csv', 'visit_occurrence'), ('conditions.csv', 'condition_occurrence'), ('medications.csv', 'drug_exposure'),
                 ('procedures.csv', 'procedure_occurrence'), ('devices.csv', 'device_exposure'), ('observations.csv', 'measurement')):
    print(f'      {src:18} {n(src):>10,} -> cdm.{tbl:22} {int(q(f"select count(*) from cdm.{tbl}")):>10,}')
print('      observations.csv + allergies + conditions also feed cdm.observation:', f'{int(q("select count(*) from cdm.observation")):,}')
print('\nvisit_occurrence orphan check (events pointing at a missing visit):',
      q("select count(*) from cdm.condition_occurrence c left join cdm.visit_occurrence v using (visit_occurrence_id) where c.visit_occurrence_id is not null and v.visit_occurrence_id is null"))
print('\nRESULT:', 'all hard checks passed' if not fails else 'FAILED: ' + ', '.join(fails))
sys.exit(1 if fails else 0)
