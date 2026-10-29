Command: python3 -m bfk.cli migrate
Input: data/accounts.jsonl with line 3 replaced by the malformed record `{"id": 99, "name": "Broken Record", "email": ` (the original lines follow it)
Exit code: 1

--- stdout ---


--- stderr ---
Traceback (most recent call last):
  File "<frozen runpy>", line 203, in _run_module_as_main
  File "<frozen runpy>", line 88, in _run_code
  File "bfk/cli.py", line 41, in <module>
    sys.exit(main())
             ~~~~^^
  File "bfk/cli.py", line 29, in main
    changed, backup_path = migrate.run(args.path, compress=args.gzip, dry_run=args.dry_run)
                           ~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "bfk/migrate.py", line 93, in run
    records = store.load_accounts(path)
  File "bfk/store.py", line 11, in load_accounts
    return [json.loads(line) for line in handle if line.strip()]
            ~~~~~~~~~~^^^^^^
  File "<stdlib>/json/__init__.py", line 352, in loads
    return _default_decoder.decode(s)
           ~~~~~~~~~~~~~~~~~~~~~~~^^^
  File "<stdlib>/json/decoder.py", line 345, in decode
    obj, end = self.raw_decode(s, idx=_w(s, 0).end())
               ~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^
  File "<stdlib>/json/decoder.py", line 363, in raw_decode
    raise JSONDecodeError("Expecting value", s, err.value) from None
json.decoder.JSONDecodeError: Expecting value: line 2 column 1 (char 46)
