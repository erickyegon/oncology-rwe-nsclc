"""Descriptive check of a filtered Synthea export: counts, stage mix vs SEER input, deaths, follow-up, age, year, sex.
Usage: python tools/cohort_summary.py <filtered_csv_dir>
Index = earliest NSCLC condition date; follow-up ends at death (event) or last encounter (censored).
"""
import csv, sys, math, statistics as st, collections
from datetime import date
csv.field_size_limit(1 << 24)
d = sys.argv[1].rstrip('/') + '/'
SEER = {'1': 20.0, '2': 8.4, '3': 19.8, '4': 51.7}
P = {k: v / sum(SEER.values()) for k, v in SEER.items()}   # scaled to sum to 1, as in the module
dt = lambda s: date.fromisoformat(s[:10])
pat = {r['Id']: r for r in csv.DictReader(open(d + 'patients.csv', encoding='utf-8'))}
idx, stage, sclc = {}, {}, set()
for r in csv.DictReader(open(d + 'conditions.csv', encoding='utf-8')):
    s, p = r['DESCRIPTION'], r['PATIENT']
    if 'Non-small cell' in s:
        x = dt(r['START']); idx[p] = min(idx.get(p, x), x)
        if 'TNM stage' in s: stage[p] = s.split('stage')[1].strip().split()[0]
    elif 'mall cell' in s and 'ung' in s:
        sclc.add(p)
last = {}
for r in csv.DictReader(open(d + 'encounters.csv', encoding='utf-8')):
    p = r['PATIENT']
    if p in idx:
        x = dt(r['START']); last[p] = max(last.get(p, x), x)

def chi2_p3(x):  # survival function, chi-square with 3 df
    return math.erfc(math.sqrt(x / 2)) + math.sqrt(2 * x / math.pi) * math.exp(-x / 2)
def wilson(k, n, z=1.96):
    if not n: return (float('nan'),) * 2
    ph = k / n; den = 1 + z * z / n; c = ph + z * z / (2 * n); h = z * math.sqrt(ph * (1 - ph) / n + z * z / (4 * n * n))
    return 100 * (c - h) / den, 100 * (c + h) / den
def q(a, f): a = sorted(a); return a[int(f * (len(a) - 1))]
def rev_km_median(times, events):
    data = sorted(zip(times, events)); n = len(data); s = 1.0; i = 0
    while i < n:
        t = data[i][0]; c = sum(1 for tt, e in data if tt == t and not e); m = sum(1 for tt, _ in data if tt == t)
        if c: s *= 1 - c / (n - i)
        if s <= 0.5: return t
        i += m
    return None

rec = {}
for p in idx:
    if p not in stage: continue
    died = bool(pat[p]['DEATHDATE'])
    end = dt(pat[p]['DEATHDATE']) if died else last.get(p, idx[p])
    rec[p] = dict(stage=stage[p], died=died, mo=max((end - idx[p]).days, 0) / 30.4375,
                  age=(idx[p] - dt(pat[p]['BIRTHDATE'])).days / 365.25, year=idx[p].year, sex=pat[p]['GENDER'])

def mix(title, ps):
    c = collections.Counter(rec[p]['stage'] for p in ps); n = sum(c.values())
    print(f'\n{title}  (n={n})')
    print(f'  {"stage":6}{"n":>6}{"%":>8}{"95% CI":>16}{"SEER %":>9}{"scaled input %":>16}')
    x2 = 0
    for k in sorted(SEER):
        lo, hi = wilson(c[k], n); e = P[k] * n
        x2 += (c[k] - e) ** 2 / e if e else 0
        print(f'  {k:6}{c[k]:>6}{100*c[k]/n if n else 0:>7.1f}%{f"{lo:.1f}-{hi:.1f}":>16}{SEER[k]:>8.1f}%{100*P[k]:>15.2f}%')
    print(f'  chi-square vs input = {x2:.2f} (df 3), p = {chi2_p3(x2):.3f}')
    return c, n

print(f'filtered patients: {len(pat)}; NSCLC: {len(idx)}; SCLC (not NSCLC): {len(sclc - set(idx))}')
print(f'NSCLC with a TNM stage code: {len(rec)}; without: {len(idx) - len(rec)}')

print('\n=== 1. Stage mix vs SEER input, all NSCLC')
call, nall = mix('all staged NSCLC', rec)
print('\n=== 1a. Restricted to age >= 50 at diagnosis (SEER cohort definition)')
c50, n50 = mix('age >= 50 at diagnosis', [p for p in rec if rec[p]['age'] >= 50])
print(f'  (excluded age < 50: {nall - n50})')
print('\n=== 1d. Stage II vs 8.4% input')
for lab, c, n in (('all', call, nall), ('age>=50', c50, n50)):
    lo, hi = wilson(c['2'], n); z = (c['2'] / n - P['2']) / math.sqrt(P['2'] * (1 - P['2']) / n)
    print(f'  {lab:8} stage II = {c["2"]}/{n} = {100*c["2"]/n:.1f}% (95% CI {lo:.1f}-{hi:.1f}); input {SEER["2"]}% (scaled {100*P["2"]:.2f}%); z = {z:+.2f}; ' + ('ABOVE input (CI excludes it)' if lo > 100*P['2'] else 'consistent with input (CI includes it)' if hi >= 100*P['2'] else 'BELOW input'))

print('\n=== 1b. Diagnosis year')
yc = collections.Counter(v['year'] for v in rec.values())
bins = collections.Counter((y // 5) * 5 for y in yc.elements())
print('  5-year bins:', ', '.join(f'{b}-{b+4}: {bins[b]}' for b in sorted(bins)))
print(f'  earliest {min(yc)}, latest {max(yc)}')
y1015 = [p for p in rec if 2010 <= rec[p]['year'] <= 2015]
print(f'  diagnosed 2010-2015: {len(y1015)} ({100*len(y1015)/nall:.1f}%)')
mix('stage mix, diagnosed 2010-2015', y1015)
print('  stage mix by 10-year era:')
for lo in sorted({(y // 10) * 10 for y in yc}):
    cc = collections.Counter(rec[p]['stage'] for p in rec if lo <= rec[p]['year'] < lo + 10); n = sum(cc.values())
    print(f'    {lo}s n={n:4}: ' + ' / '.join(f'{k} {100*cc[k]/n:.0f}%' for k in sorted(SEER)))

print('\n=== 1c. Sex split and age at diagnosis by stage')
sx = collections.Counter(v['sex'] for v in rec.values())
print(f'  overall: M {sx["M"]} ({100*sx["M"]/nall:.1f}%), F {sx["F"]} ({100*sx["F"]/nall:.1f}%)')
print(f'  {"stage":6}{"n":>5}{"M":>6}{"F":>6}{"%F":>7}{"age mean (SD)":>16}{"median [IQR]":>16}{"range":>9}{"deaths":>8}{"med obs mo":>12}{"med f/u rKM":>13}')
for k in sorted(SEER):
    r = [v for v in rec.values() if v['stage'] == k]; a = [v['age'] for v in r]; n = len(r)
    f = sum(1 for v in r if v['sex'] == 'F'); mo = [v['mo'] for v in r]
    fu = rev_km_median(mo, [v['died'] for v in r])
    print(f'  {k:6}{n:>5}{n-f:>6}{f:>6}{100*f/n:>6.0f}%{st.mean(a):>9.1f} ({st.stdev(a):.1f}){st.median(a):>9.1f} [{q(a,.25):.0f}-{q(a,.75):.0f}]{min(a):>5.0f}-{max(a):.0f}{sum(v["died"] for v in r):>8}{st.median(mo):>12.1f}{(f"{fu:.1f}" if fu is not None else "NR"):>13}')
a = [v['age'] for v in rec.values()]
print(f'  all: age mean {st.mean(a):.1f} (SD {st.stdev(a):.1f}), median {st.median(a):.1f} [{q(a,.25):.0f}-{q(a,.75):.0f}], range {min(a):.0f}-{max(a):.0f}; deaths {sum(v["died"] for v in rec.values())}/{nall}')
print('\n  stage mix by sex:')
for s_ in ('F', 'M'):
    cc = collections.Counter(v['stage'] for v in rec.values() if v['sex'] == s_); n = sum(cc.values())
    print(f'    {s_} n={n:4}: ' + ' / '.join(f'{k} {100*cc[k]/n:.1f}%' for k in sorted(SEER)))
