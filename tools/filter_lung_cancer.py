"""Keep only patients with a lung cancer diagnosis in a Synthea CSV export (disk-space reduction).
Usage: python tools/filter_lung_cancer.py <in_csv_dir> <out_csv_dir> [--only a.csv,b.csv]
--only re-filters just those files (to resume after a failure); patient IDs are always recomputed.
Reference tables (organizations, providers, payers) are copied whole.
"""
import csv, sys, os, re
src, dst = sys.argv[1], sys.argv[2]
only = set(sys.argv[4].split(',')) if len(sys.argv) > 4 and sys.argv[3] == '--only' else None
os.makedirs(dst, exist_ok=True)
csv.field_size_limit(1 << 24)
pat = re.compile(r'lung', re.I)
ok = re.compile(r'cancer|carcinoma|neoplasm', re.I)
ids = set()
with open(os.path.join(src, 'conditions.csv'), encoding='utf-8', newline='') as f:
    r = csv.reader(f); h = next(r); ip, idsc = h.index('PATIENT'), h.index('DESCRIPTION')
    for row in r:
        d = row[idsc]
        if pat.search(d) and ok.search(d) and 'uspected' not in d:
            ids.add(row[ip])
print('lung cancer patients:', len(ids), flush=True)
whole = {'organizations.csv', 'providers.csv', 'payers.csv'}
for fn in sorted(os.listdir(src)):
    if not fn.endswith('.csv') or (only and fn not in only): continue
    n = k = 0
    with open(os.path.join(src, fn), encoding='utf-8', newline='') as fi, \
         open(os.path.join(dst, fn), 'w', encoding='utf-8', newline='') as fo:
        r = csv.reader(fi); w = csv.writer(fo, lineterminator='\n'); h = next(r); w.writerow(h)
        key = None if fn in whole else next((c for c in ('Id', 'PATIENT', 'PATIENT_ID') if c in h and (c != 'Id' or fn == 'patients.csv')), None)
        if key is None and fn not in whole:
            raise SystemExit(f'{fn}: no patient key column in {h}')
        ik = h.index(key) if key else None
        for row in r:
            n += 1
            if key is None or row[ik] in ids:
                w.writerow(row); k += 1
    print(f'{fn}: {k}/{n}', flush=True)
