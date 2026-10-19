"""Tests for tools/filter_lung_cancer.py on a tiny hand-made Synthea-style export (standard library only; run with pytest)."""
import csv
import subprocess
import sys
from pathlib import Path

TOOL = Path(__file__).resolve().parents[2] / "tools" / "filter_lung_cancer.py"


def write(path, header, rows):
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)


def read(path):
    with open(path, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def make_export(d: Path):
    d.mkdir()
    write(d / "patients.csv", ["Id", "BIRTHDATE"], [["p1", "1950-01-01"], ["p2", "1960-01-01"], ["p3", "1955-01-01"]])
    write(d / "conditions.csv", ["PATIENT", "DESCRIPTION"], [
        ["p1", "Non-small cell lung cancer (disorder)"],        # kept
        ["p2", "Suspected lung cancer (situation)"],            # suspected: excluded
        ["p2", "Acute bronchitis (disorder)"],
        ["p3", "Primary small cell carcinoma of lung (disorder)"],  # lung carcinoma: kept
    ])
    write(d / "encounters.csv", ["Id", "PATIENT"], [["e1", "p1"], ["e2", "p2"], ["e3", "p3"], ["e4", "p1"]])
    write(d / "organizations.csv", ["Id", "NAME"], [["o1", "A"], ["o2", "B"]])


def run(src, dst):
    return subprocess.run([sys.executable, str(TOOL), str(src), str(dst)], capture_output=True, text=True, check=True)


def test_keeps_only_lung_cancer_patients_and_copies_reference_tables(tmp_path):
    src, dst = tmp_path / "in", tmp_path / "out"
    make_export(src)
    run(src, dst)
    assert {r["Id"] for r in read(dst / "patients.csv")} == {"p1", "p3"}
    assert [r["Id"] for r in read(dst / "encounters.csv")] == ["e1", "e3", "e4"]
    assert len(read(dst / "organizations.csv")) == 2           # reference table copied whole


def test_patient_ids_outside_the_cohort_never_appear(tmp_path):
    src, dst = tmp_path / "in", tmp_path / "out"
    make_export(src)
    run(src, dst)
    kept = {r["Id"] for r in read(dst / "patients.csv")}
    for fn in ("encounters.csv", "conditions.csv"):
        assert {r["PATIENT"] for r in read(dst / fn)} <= kept


def test_reports_the_number_of_lung_cancer_patients(tmp_path):
    src, dst = tmp_path / "in", tmp_path / "out"
    make_export(src)
    assert "lung cancer patients: 2" in run(src, dst).stdout
