import os
import time


def fetch_jobs(limit):
    return []


def process(job):
    pass


def batch_loop():
    while True:
        max_batch = int(os.environ.get("MAX_BATCH", "50"))
        jobs = fetch_jobs(max_batch)
        for job in jobs:
            process(job)
        if not jobs:
            time.sleep(5)


if __name__ == "__main__":
    batch_loop()
