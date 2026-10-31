from csvtools import read_csv_rows


def _load_rows(path):
    return read_csv_rows(path)


def summarize(path):
    rows = _load_rows(path)
    return len(rows)
