# Why the importer batches writes

Write one row per transaction and the import crawls like rush-hour traffic.

The batch size lives in `IMPORT_BATCH_SIZE`, which is the seam where all the tuning
happens.

The importer opens one transaction per 500 rows and commits it before it reads the
next file.
