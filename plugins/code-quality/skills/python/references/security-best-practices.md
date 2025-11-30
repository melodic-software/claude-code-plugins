# Python Security Best Practices

## Table of Contents

- [Overview](#overview)
- [OWASP Top 10 for Python (2024)](#owasp-top-10-for-python-2024)
- [1. SQL Injection Prevention](#1-sql-injection-prevention)
- [2. Command Injection Prevention](#2-command-injection-prevention)
- [3. Cross-Site Scripting (XSS) Prevention](#3-cross-site-scripting-xss-prevention)
- [4. Input Validation with Pydantic](#4-input-validation-with-pydantic)
- [5. Secrets Management](#5-secrets-management)
- [6. Dependency Security Scanning](#6-dependency-security-scanning)
- [7. Secure Deserialization](#7-secure-deserialization)
- [8. Cryptography Best Practices](#8-cryptography-best-practices)
- [9. Security Linting with Bandit](#9-security-linting-with-bandit)
- [10. HTTPS and TLS Best Practices](#10-https-and-tls-best-practices)
- [11. Security Headers (Web Applications)](#11-security-headers-web-applications)
- [12. Logging and Monitoring](#12-logging-and-monitoring)
- [13. Rate Limiting](#13-rate-limiting)
- [Summary Checklist](#summary-checklist)

## Overview

This guide provides comprehensive security best practices for Python development, covering the OWASP Top 10 vulnerabilities and Python-specific security patterns. All recommendations are backed by official documentation and industry standards.

**Official Sources:**

- OWASP Cheat Sheet Series: <https://cheatsheetseries.owasp.org/>
- Python Cryptography Library: <https://cryptography.io/>
- Bandit Security Linter: <https://bandit.readthedocs.io/>
- Python Security Documentation: <https://docs.python.org/3/library/security_warnings.html>

**Last Verified:** 2025-01-17

---

## OWASP Top 10 for Python (2024)

The OWASP Top 10 represents the most critical security risks to web applications:

1. **Broken Access Control** - Improperly configured restrictions on authenticated users
2. **Cryptographic Failures** - Weak or missing encryption of sensitive data
3. **Injection** - SQL injection, command injection, code injection attacks
4. **Insecure Design** - Missing security controls in the design phase
5. **Security Misconfiguration** - Improper security settings across the application stack
6. **Vulnerable and Outdated Components** - Using libraries with known vulnerabilities
7. **Identification and Authentication Failures** - Weak authentication mechanisms
8. **Software and Data Integrity Failures** - Compromised dependencies and insecure CI/CD
9. **Security Logging and Monitoring Failures** - Insufficient tracking of security events
10. **Server-Side Request Forgery (SSRF)** - Unvalidated user-supplied URLs

**Source:** OWASP Top 10 2021 (<https://owasp.org/Top10/>)

---

## 1. SQL Injection Prevention

### Overview: SQL Injection Attacks

SQL injection occurs when attackers insert malicious SQL code into input fields. This is one of the most common and dangerous vulnerabilities.

**Official Source:** OWASP SQL Injection Prevention Cheat Sheet (<https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html>)

### Vulnerable Code (NEVER DO THIS)

```python
# ❌ DANGEROUS - String formatting with user input
user_id = request.args.get('id')
query = f"SELECT * FROM users WHERE id = {user_id}"
cursor.execute(query)

# ❌ DANGEROUS - String concatenation
username = request.form['username']
query = "SELECT * FROM users WHERE username = '" + username + "'"
cursor.execute(query)

# ❌ DANGEROUS - % formatting
query = "SELECT * FROM users WHERE email = '%s'" % user_email
cursor.execute(query)
```

**Attack Example:** An attacker could input `1 OR 1=1` or `'; DROP TABLE users; --` to exploit these vulnerabilities.

### Safe Code - Parameterized Queries

```python
# ✅ SAFE - SQLite parameterized query
import sqlite3

user_id = request.args.get('id')
cursor.execute("SELECT * FROM users WHERE id = ?", (user_id,))

# ✅ SAFE - PostgreSQL with psycopg2
import psycopg2

username = request.form['username']
cursor.execute("SELECT * FROM users WHERE username = %s", (username,))

# ✅ SAFE - MySQL with mysql-connector-python
import mysql.connector

email = request.form['email']
cursor.execute("SELECT * FROM users WHERE email = %s", (email,))
```

### Safe Code - ORM Usage (SQLAlchemy)

```python
# ✅ SAFE - SQLAlchemy ORM
from sqlalchemy import text
from models import User

# ORM query (inherently safe)
user = User.query.filter_by(username=username).first()

# Text query with parameters
user_id = request.args.get('id')
result = db.session.execute(
    text("SELECT * FROM users WHERE id = :user_id"),
    {"user_id": user_id}
)
```

### Safe Code - Django ORM

```python
# ✅ SAFE - Django ORM
from django.contrib.auth.models import User

# ORM query (inherently safe)
user = User.objects.get(username=username)

# Raw query with parameters (when necessary)
from django.db import connection

with connection.cursor() as cursor:
    cursor.execute("SELECT * FROM users WHERE id = %s", [user_id])
```

**Key Principle:** ALWAYS use parameterized queries or ORM methods. NEVER use string formatting, concatenation, or interpolation with user input in SQL queries.

---

## 2. Command Injection Prevention

### Overview: Command Injection Attacks

Command injection occurs when an application executes OS commands with unvalidated user input, allowing attackers to run arbitrary commands on the server.

**Official Source:** OWASP Injection Prevention Cheat Sheet (<https://cheatsheetseries.owasp.org/cheatsheets/Injection_Prevention_Cheat_Sheet.html>)

### Vulnerable Code: Command Injection Examples

```python
# ❌ DANGEROUS - shell=True with user input
import subprocess

filename = request.args.get('file')
subprocess.run(f"cat {filename}", shell=True)

# ❌ DANGEROUS - os.system with user input
import os

user_input = request.form['command']
os.system(f"ls {user_input}")
```

**Attack Example:** An attacker could input `file.txt; rm -rf /` to delete files.

### Safe Code - Argument Lists

```python
# ✅ SAFE - Use argument list without shell=True
import subprocess

filename = request.args.get('file')

# Validate filename first
if not filename.replace('.', '').replace('_', '').isalnum():
    raise ValueError("Invalid filename")

# Use list of arguments (shell=False is default)
result = subprocess.run(['cat', filename], capture_output=True, text=True)

# ✅ SAFE - More complex example
import shlex

user_path = request.args.get('path')

# Validate path
if '..' in user_path or user_path.startswith('/'):
    raise ValueError("Invalid path")

# Use argument list for safety
subprocess.run(['ls', '-l', user_path], capture_output=True)
```

### Input Validation for Command Arguments

```python
# ✅ SAFE - Whitelist validation
import re

def safe_filename(filename):
    """Only allow alphanumeric, dots, dashes, underscores"""
    if not re.match(r'^[a-zA-Z0-9._-]+$', filename):
        raise ValueError("Invalid filename")

    # Additional checks
    if '..' in filename or filename.startswith('/'):
        raise ValueError("Path traversal attempt")

    return filename

# Usage
filename = safe_filename(request.args.get('file'))
subprocess.run(['cat', filename], capture_output=True)
```

**Best Practices:**

- NEVER use `shell=True` with user input
- Use argument lists instead of string commands
- Validate and sanitize all user input with whitelists
- Avoid `os.system()`, `os.popen()`, and similar functions

---

## 3. Cross-Site Scripting (XSS) Prevention

### Overview: XSS Attack Prevention

XSS attacks inject malicious scripts into web pages viewed by other users. Proper output encoding and framework protections are essential.

**Official Source:** OWASP XSS Prevention Cheat Sheet (<https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html>)

### Vulnerable Code (Flask)

```python
# ❌ DANGEROUS - Unescaped user input
from flask import Flask, request

@app.route('/vulnerable')
def vulnerable():
    user_input = request.args.get('name', '')
    # Direct string interpolation renders HTML
    return f"<h1>Hello {user_input}</h1>"
```

**Attack Example:** `?name=<script>alert('XSS')</script>` would execute JavaScript.

### Safe Code - Framework Auto-Escaping

```python
# ✅ SAFE - Flask with Jinja2 templates (auto-escapes by default)
from flask import Flask, render_template, request

@app.route('/safe')
def safe():
    user_input = request.args.get('name', '')
    # Jinja2 auto-escapes HTML by default
    return render_template('welcome.html', name=user_input)
```

**Template (welcome.html):**

```html
<!-- Auto-escaped by Jinja2 -->
<h1>Hello {{ name }}</h1>
```

### Safe Code - Django Templates

```python
# ✅ SAFE - Django templates (auto-escape by default)
from django.shortcuts import render

def welcome(request):
    user_input = request.GET.get('name', '')
    # Django templates auto-escape HTML
    return render(request, 'welcome.html', {'name': user_input})
```

**Django Template:**

```html
<!-- Auto-escaped by Django -->
<h1>Hello {{ name }}</h1>
```

### Manual Escaping When Needed

```python
# ✅ SAFE - Manual HTML escaping
from html import escape
from flask import Flask

@app.route('/manual')
def manual_escape():
    user_input = request.args.get('comment', '')
    safe_input = escape(user_input)
    return f"<p>{safe_input}</p>"

# ✅ SAFE - MarkupSafe (used by Flask/Jinja2)
from markupsafe import escape

@app.route('/markup')
def markup_safe():
    user_input = request.args.get('text', '')
    return f"<div>{escape(user_input)}</div>"
```

### Content Security Policy Headers

```python
# ✅ DEFENSE IN DEPTH - Add CSP headers
from flask import Flask, Response

@app.after_request
def add_security_headers(response):
    response.headers['Content-Security-Policy'] = (
        "default-src 'self'; "
        "script-src 'self'; "
        "style-src 'self' 'unsafe-inline'; "
        "img-src 'self' data:; "
        "font-src 'self'; "
        "connect-src 'self'; "
        "frame-ancestors 'none';"
    )
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['X-XSS-Protection'] = '1; mode=block'
    return response
```

**Best Practices:**

- Use framework auto-escaping (Jinja2, Django templates)
- Never mark user input as safe (`| safe` in Jinja2, `mark_safe()` in Django)
- Implement Content Security Policy headers
- Validate and sanitize input on the server side

---

## 4. Input Validation with Pydantic

### Overview: Input Validation Best Practices

Input validation prevents many security vulnerabilities by ensuring data conforms to expected formats before processing.

**Official Source:** Pydantic Documentation (<https://docs.pydantic.dev/>)

### Basic Validation

```python
# ✅ Type validation and constraints
from pydantic import BaseModel, Field, validator, EmailStr
from typing import Optional

class UserRegistration(BaseModel):
    username: str = Field(..., min_length=3, max_length=20, pattern=r'^[a-zA-Z0-9_]+$')
    email: EmailStr
    age: int = Field(..., ge=13, le=120)
    password: str = Field(..., min_length=8)

    @validator('username')
    def username_alphanumeric(cls, v):
        if not v.replace('_', '').isalnum():
            raise ValueError('Username must be alphanumeric')
        return v

    @validator('password')
    def password_strength(cls, v):
        if not any(c.isupper() for c in v):
            raise ValueError('Password must contain uppercase')
        if not any(c.islower() for c in v):
            raise ValueError('Password must contain lowercase')
        if not any(c.isdigit() for c in v):
            raise ValueError('Password must contain digit')
        return v

# Usage with FastAPI
from fastapi import FastAPI, HTTPException

app = FastAPI()

@app.post("/register")
async def register(user: UserRegistration):
    # Data is validated automatically
    # user.username is guaranteed to match pattern
    # user.email is guaranteed to be valid email
    return {"message": "User registered successfully"}
```

### Advanced Validation Examples

```python
from pydantic import BaseModel, HttpUrl, constr, conint, validator
from typing import List
from datetime import datetime

class APIRequest(BaseModel):
    # Constrained string (3-50 chars, alphanumeric + spaces)
    title: constr(min_length=3, max_length=50, pattern=r'^[a-zA-Z0-9 ]+$')

    # Constrained integer (1-100)
    priority: conint(ge=1, le=100)

    # HTTP URL validation
    callback_url: HttpUrl

    # List with length constraints
    tags: List[str] = Field(..., min_items=1, max_items=10)

    # Date validation
    due_date: datetime

    @validator('due_date')
    def due_date_must_be_future(cls, v):
        if v < datetime.now():
            raise ValueError('Due date must be in the future')
        return v

    @validator('tags')
    def validate_tags(cls, v):
        # Each tag must be 1-20 chars
        for tag in v:
            if not (1 <= len(tag) <= 20):
                raise ValueError('Tags must be 1-20 characters')
            if not tag.replace('-', '').isalnum():
                raise ValueError('Tags must be alphanumeric')
        return v
```

### File Upload Validation

```python
from pydantic import BaseModel, Field, validator
from fastapi import FastAPI, UploadFile, File, HTTPException

class FileUploadValidator(BaseModel):
    filename: str
    content_type: str
    size: int

    @validator('filename')
    def validate_filename(cls, v):
        # Only allow safe characters
        if not v.replace('.', '').replace('_', '').replace('-', '').isalnum():
            raise ValueError('Invalid filename')

        # Check extension whitelist
        allowed_extensions = ['.jpg', '.jpeg', '.png', '.pdf', '.txt']
        if not any(v.lower().endswith(ext) for ext in allowed_extensions):
            raise ValueError('File type not allowed')

        return v

    @validator('content_type')
    def validate_content_type(cls, v):
        allowed_types = [
            'image/jpeg', 'image/png',
            'application/pdf', 'text/plain'
        ]
        if v not in allowed_types:
            raise ValueError('Content type not allowed')
        return v

    @validator('size')
    def validate_size(cls, v):
        max_size = 10 * 1024 * 1024  # 10MB
        if v > max_size:
            raise ValueError('File too large')
        return v

@app.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    # Validate file
    validator = FileUploadValidator(
        filename=file.filename,
        content_type=file.content_type,
        size=file.size
    )

    # Process validated file
    return {"filename": validator.filename}
```

**Best Practices:**

- Define strict schemas for all input data
- Use type constraints and validators
- Implement whitelist validation (only allow known good values)
- Validate file uploads (name, type, size, content)
- Use Pydantic with FastAPI or standalone

---

## 5. Secrets Management

### Overview: Secure Secrets Handling

Never hardcode secrets in source code. Use environment variables for development and dedicated secrets managers for production.

**Official Sources:**

- AWS Secrets Manager Best Practices (<https://docs.aws.amazon.com/secretsmanager/latest/userguide/best-practices.html>)
- Azure Key Vault (<https://docs.microsoft.com/en-us/azure/key-vault/>)

### NEVER Do This: Hardcoded Secrets

```python
# ❌ DANGEROUS - Hardcoded secrets
API_KEY = "sk_live_abc123xyz789"
DATABASE_URL = "postgresql://user:password123@localhost/db"
SECRET_KEY = "my-secret-key-12345"

# ❌ DANGEROUS - Committed to version control
config = {
    "aws_access_key": "AKIAIOSFODNN7EXAMPLE",
    "aws_secret_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
}
```

### Safe - Environment Variables (Development)

```python
# ✅ SAFE - Environment variables
import os

API_KEY = os.getenv('API_KEY')
DATABASE_URL = os.getenv('DATABASE_URL')
SECRET_KEY = os.getenv('SECRET_KEY')

# Fail fast if required secrets missing
if not API_KEY:
    raise ValueError("API_KEY environment variable not set")

# ✅ SAFE - python-dotenv for local development
from dotenv import load_dotenv
import os

# Load from .env file (add .env to .gitignore!)
load_dotenv()

API_KEY = os.getenv('API_KEY')
DATABASE_URL = os.getenv('DATABASE_URL')
```

**.env file (NEVER commit to git):**

```bash
# Add .env to .gitignore!
API_KEY=your-api-key-here
DATABASE_URL=postgresql://user:pass@localhost/db
SECRET_KEY=your-secret-key-here
```

**.gitignore:**

```text
.env
.env.local
.env.*.local
*.env
```

### Safe - AWS Secrets Manager (Production)

```python
# ✅ SAFE - AWS Secrets Manager
import boto3
import json
from botocore.exceptions import ClientError

def get_secret(secret_name, region_name='us-east-1'):
    """Retrieve secret from AWS Secrets Manager"""
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name=region_name
    )

    try:
        response = client.get_secret_value(SecretId=secret_name)
    except ClientError as e:
        # Handle specific errors
        if e.response['Error']['Code'] == 'ResourceNotFoundException':
            raise ValueError(f"Secret {secret_name} not found")
        elif e.response['Error']['Code'] == 'InvalidRequestException':
            raise ValueError(f"Invalid request for secret {secret_name}")
        elif e.response['Error']['Code'] == 'InvalidParameterException':
            raise ValueError(f"Invalid parameter for secret {secret_name}")
        else:
            raise

    # Parse and return secret
    if 'SecretString' in response:
        return json.loads(response['SecretString'])
    else:
        # Binary secret
        return response['SecretBinary']

# Usage
db_credentials = get_secret('prod/database/credentials')
DATABASE_URL = f"postgresql://{db_credentials['username']}:{db_credentials['password']}@{db_credentials['host']}/{db_credentials['database']}"
```

### Safe - Azure Key Vault (Production)

```python
# ✅ SAFE - Azure Key Vault
from azure.keyvault.secrets import SecretClient
from azure.identity import DefaultAzureCredential

def get_azure_secret(vault_url, secret_name):
    """Retrieve secret from Azure Key Vault"""
    credential = DefaultAzureCredential()
    client = SecretClient(vault_url=vault_url, credential=credential)

    secret = client.get_secret(secret_name)
    return secret.value

# Usage
VAULT_URL = "https://my-vault.vault.azure.net/"
API_KEY = get_azure_secret(VAULT_URL, "api-key")
DATABASE_PASSWORD = get_azure_secret(VAULT_URL, "database-password")
```

### Secret Rotation Example

```python
# ✅ SAFE - Secret rotation with caching
from datetime import datetime, timedelta
import boto3

class SecretCache:
    def __init__(self, secret_name, ttl_minutes=15):
        self.secret_name = secret_name
        self.ttl = timedelta(minutes=ttl_minutes)
        self._secret = None
        self._last_fetch = None
        self.client = boto3.client('secretsmanager')

    def get_secret(self):
        """Get secret with automatic refresh"""
        now = datetime.now()

        # Refresh if expired or never fetched
        if self._secret is None or (now - self._last_fetch) > self.ttl:
            response = self.client.get_secret_value(SecretId=self.secret_name)
            self._secret = json.loads(response['SecretString'])
            self._last_fetch = now

        return self._secret

# Usage
db_secret = SecretCache('prod/database/credentials', ttl_minutes=15)
credentials = db_secret.get_secret()
```

**Best Practices:**

- NEVER commit secrets to version control
- Use `.env` files for local development (add to `.gitignore`)
- Use AWS Secrets Manager or Azure Key Vault for production
- Implement secret rotation
- Use IAM roles and least privilege access
- Audit secret access with logging
- Separate secrets by environment (dev/staging/prod)

---

## 6. Dependency Security Scanning

### Overview: Vulnerability Detection

Regularly scan dependencies for known vulnerabilities and keep them updated.

**Official Sources:**

- pip-audit (<https://pypi.org/project/pip-audit/>)
- Safety (<https://pypi.org/project/safety/>)
- Snyk (<https://snyk.io/>)

### pip-audit (Official Python Tool)

```bash
# Install pip-audit
pip install pip-audit

# Scan current environment
pip-audit

# Scan requirements file
pip-audit -r requirements.txt

# Output in JSON format
pip-audit --format json

# Fix vulnerabilities automatically
pip-audit --fix
```

**Example Output:**

```text
Found 2 known vulnerabilities in 2 packages
Name    Version ID               Fix Versions
------- ------- ---------------- ------------
django  2.2.0   PYSEC-2021-439   3.2.13, 3.1.14, 2.2.28
pillow  8.0.0   GHSA-8vj2-vxx3-667w 8.3.2
```

### Safety (Comprehensive Database)

```bash
# Install Safety
pip install safety

# Scan current environment
safety check

# Scan requirements file
safety check -r requirements.txt

# Output in JSON
safety check --json

# Check only production dependencies
safety check --file requirements.txt
```

**CI/CD Integration:**

```yaml
# .github/workflows/security.yml
name: Security Scan

on: [push, pull_request]

jobs:
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          pip install -r requirements.txt
          pip install pip-audit safety

      - name: Run pip-audit
        run: pip-audit

      - name: Run Safety check
        run: safety check
```

### Dependabot Configuration

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "pip"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
    reviewers:
      - "security-team"
    labels:
      - "dependencies"
      - "security"
```

### Pin Dependencies Safely

```txt
# requirements.txt - Pin major/minor versions
Django>=4.2,<5.0
requests>=2.31,<3.0
cryptography>=41.0,<42.0
pydantic>=2.0,<3.0

# Or use pip-tools for reproducible builds
# requirements.in
Django~=4.2
requests~=2.31

# Generate locked requirements.txt
# pip-compile requirements.in
```

**Best Practices:**

- Run `pip-audit` or `safety check` regularly (weekly minimum)
- Enable Dependabot or Snyk for automated scanning
- Pin dependency versions in requirements.txt
- Test updates in staging before production
- Subscribe to security advisories for critical packages
- Use virtual environments to isolate dependencies

---

## 7. Secure Deserialization

### Overview: Deserialization Security

Never unpickle untrusted data. Pickle can execute arbitrary code during deserialization.

**Official Source:** Python pickle documentation (<https://docs.python.org/3/library/pickle.html>)

### NEVER Do This: Unpickling Untrusted Data

```python
# ❌ DANGEROUS - Unpickling untrusted data
import pickle

# User-supplied data from web request
user_data = request.get_data()
obj = pickle.loads(user_data)  # ARBITRARY CODE EXECUTION!
```

**Attack Example:** Attacker can craft pickle payload to execute `os.system('rm -rf /')` or similar.

### Safe Alternatives - JSON

```python
# ✅ SAFE - Use JSON for untrusted data
import json

# Serialize
data = {'name': 'Alice', 'age': 30}
json_str = json.dumps(data)

# Deserialize (safe from code execution)
user_data = request.get_data()
obj = json.loads(user_data)

# ✅ SAFE - With validation
from pydantic import BaseModel

class UserData(BaseModel):
    name: str
    age: int

user_data = request.get_data()
parsed = json.loads(user_data)
validated = UserData(**parsed)  # Type-safe and validated
```

### Safe Alternatives - MessagePack

```python
# ✅ SAFE - MessagePack for binary data
import msgpack

# Serialize
data = {'name': 'Alice', 'age': 30}
packed = msgpack.packb(data)

# Deserialize (safe from code execution)
unpacked = msgpack.unpackb(packed)
```

### When Pickle is Necessary (Trusted Data Only)

```python
# ⚠️ USE WITH CAUTION - Only for trusted data
import pickle
import hmac
import hashlib

SECRET_KEY = os.getenv('PICKLE_SECRET_KEY')

def safe_pickle_dump(obj):
    """Pickle with HMAC signature"""
    pickled = pickle.dumps(obj)
    signature = hmac.new(
        SECRET_KEY.encode(),
        pickled,
        hashlib.sha256
    ).hexdigest()
    return signature + pickled.hex()

def safe_pickle_load(data):
    """Unpickle with HMAC verification"""
    signature = data[:64]
    pickled_hex = data[64:]
    pickled = bytes.fromhex(pickled_hex)

    # Verify signature
    expected_sig = hmac.new(
        SECRET_KEY.encode(),
        pickled,
        hashlib.sha256
    ).hexdigest()

    if not hmac.compare_digest(signature, expected_sig):
        raise ValueError("Invalid signature - data tampered")

    return pickle.loads(pickled)
```

**Best Practices:**

- NEVER use pickle with untrusted data
- Use JSON for web APIs and user input
- Use MessagePack for binary serialization
- If pickle is required, use HMAC signatures
- Consider Protocol Buffers or Cap'n Proto for structured data

---

## 8. Cryptography Best Practices

### Overview: Cryptographic Operations

Use the `cryptography` library for all cryptographic operations. Never implement crypto yourself.

**Official Source:** Python Cryptography Library (<https://cryptography.io/>)

### Password Hashing

```python
# ✅ SAFE - bcrypt for password hashing
import bcrypt

def hash_password(password: str) -> bytes:
    """Hash password with bcrypt"""
    password_bytes = password.encode('utf-8')
    salt = bcrypt.gensalt(rounds=12)  # Cost factor: 12 is good default
    return bcrypt.hashpw(password_bytes, salt)

def verify_password(password: str, hashed: bytes) -> bool:
    """Verify password against hash"""
    password_bytes = password.encode('utf-8')
    return bcrypt.checkpw(password_bytes, hashed)

# Usage
hashed = hash_password("user_password_123")
is_valid = verify_password("user_password_123", hashed)  # True
```

### Alternative - Argon2 (More Secure)

```python
# ✅ SAFE - Argon2 (recommended for new systems)
from argon2 import PasswordHasher

ph = PasswordHasher()

def hash_password_argon2(password: str) -> str:
    """Hash password with Argon2"""
    return ph.hash(password)

def verify_password_argon2(password: str, hashed: str) -> bool:
    """Verify password against Argon2 hash"""
    try:
        ph.verify(hashed, password)
        return True
    except:
        return False
```

### Symmetric Encryption (Fernet)

```python
# ✅ SAFE - Fernet symmetric encryption
from cryptography.fernet import Fernet

# Generate key (store securely!)
key = Fernet.generate_key()
cipher = Fernet(key)

# Encrypt
message = b"Secret data"
encrypted = cipher.encrypt(message)

# Decrypt
decrypted = cipher.decrypt(encrypted)
assert decrypted == message
```

### Key Derivation from Password

```python
# ✅ SAFE - PBKDF2 key derivation
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
import os
import base64

def derive_key(password: str, salt: bytes = None) -> tuple:
    """Derive encryption key from password"""
    if salt is None:
        salt = os.urandom(16)

    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt,
        iterations=480000,  # OWASP recommended minimum (2023)
    )

    key = base64.urlsafe_b64encode(kdf.derive(password.encode()))
    return key, salt

# Usage
password = "user_password"
key, salt = derive_key(password)

# Store salt with encrypted data
# To decrypt, derive key again with same password and salt
```

### Secure Random Numbers

```python
# ✅ SAFE - Use secrets module for cryptographic randomness
import secrets

# Random token (URL-safe)
token = secrets.token_urlsafe(32)

# Random hex token
hex_token = secrets.token_hex(16)

# Random bytes
random_bytes = secrets.token_bytes(32)

# Random choice (e.g., for password generation)
import string
alphabet = string.ascii_letters + string.digits
password = ''.join(secrets.choice(alphabet) for i in range(16))

# ❌ NEVER use random module for security
import random
# random.random() is NOT cryptographically secure!
```

### NEVER Do This: Weak Hashing

```python
# ❌ DANGEROUS - Weak hashing algorithms
import hashlib

# MD5 - BROKEN, do not use
md5_hash = hashlib.md5(password.encode()).hexdigest()

# SHA1 - BROKEN, do not use
sha1_hash = hashlib.sha1(password.encode()).hexdigest()

# SHA256 without salt - WEAK for passwords
sha256_hash = hashlib.sha256(password.encode()).hexdigest()

# ❌ DANGEROUS - Using random for security
import random
token = ''.join(random.choices(string.ascii_letters, k=16))  # NOT SECURE!
```

**Best Practices:**

- Use bcrypt or Argon2 for password hashing
- Use Fernet for symmetric encryption
- Use `secrets` module for random tokens
- NEVER use MD5, SHA1, or unsalted SHA256 for passwords
- NEVER use `random` module for security purposes
- Use at least 480,000 iterations for PBKDF2 (OWASP 2023 recommendation)

---

## 9. Security Linting with Bandit

### Overview: Static Security Analysis

Bandit is a static analysis tool that finds common security issues in Python code.

**Official Source:** Bandit Documentation (<https://bandit.readthedocs.io/>)

### Installation and Basic Usage

```bash
# Install Bandit
pip install bandit

# Scan a file
bandit myfile.py

# Scan directory recursively
bandit -r src/

# Output to JSON
bandit -r src/ -f json -o bandit-report.json

# Exclude test files
bandit -r src/ --exclude src/tests/

# Filter by severity
bandit -r src/ --severity-level medium
```

### Configuration File

```yaml
# .bandit
# or pyproject.toml: [tool.bandit]
# or bandit.yaml

exclude_dirs:
  - tests
  - venv
  - .venv

tests:
  - B201  # flask_debug_true
  - B301  # pickle
  - B306  # mktemp_q
  - B602  # subprocess_popen_with_shell_equals_true
  - B608  # hardcoded_sql_expressions

skips:
  - B101  # assert_used (if using asserts in production)
  - B601  # paramiko_calls (if false positive)
```

### Common Issues Bandit Detects

```python
# B201: Flask debug mode enabled
app.run(debug=True)  # ⚠️ SECURITY ISSUE

# B301: Pickle usage
import pickle
pickle.loads(user_data)  # ⚠️ SECURITY ISSUE

# B303: Insecure hash function
import hashlib
hashlib.md5(data)  # ⚠️ SECURITY ISSUE

# B324: Insecure hash function for password
import hashlib
hashlib.sha256(password.encode())  # ⚠️ SECURITY ISSUE

# B501: Request with verify=False
import requests
requests.get(url, verify=False)  # ⚠️ SECURITY ISSUE

# B602: shell=True with subprocess
subprocess.call("ls " + user_input, shell=True)  # ⚠️ SECURITY ISSUE

# B608: SQL injection possibility
query = "SELECT * FROM users WHERE id = " + user_id  # ⚠️ SECURITY ISSUE
```

### Suppressing False Positives

```python
# Suppress specific test
import pickle
data = pickle.loads(trusted_data)  # nosec B301

# Suppress multiple tests
subprocess.call(cmd, shell=True)  # nosec B602, B607

# Suppress all on line
eval(safe_expression)  # nosec
```

### CI/CD Integration

```yaml
# .github/workflows/security.yml
name: Security Scan

on: [push, pull_request]

jobs:
  bandit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Install Bandit
        run: pip install bandit

      - name: Run Bandit
        run: bandit -r src/ -f json -o bandit-report.json

      - name: Upload results
        uses: actions/upload-artifact@v3
        with:
          name: bandit-report
          path: bandit-report.json
```

**Best Practices:**

- Run Bandit on every commit (CI/CD integration)
- Fix high and medium severity issues
- Review low severity issues for false positives
- Use `# nosec` sparingly with justification
- Configure exclusions in `.bandit` file
- Combine with other tools (pip-audit, mypy, pylint)

---

## 10. HTTPS and TLS Best Practices

### Overview: Secure Communication

Always use HTTPS in production and verify TLS certificates.

### Requests Library Best Practices

```python
# ✅ SAFE - Default behavior (verify=True)
import requests

response = requests.get('https://api.example.com/data')
# Certificate is verified automatically

# ✅ SAFE - Explicit verification
response = requests.get('https://api.example.com/data', verify=True)

# ✅ SAFE - Custom CA bundle
response = requests.get(
    'https://api.example.com/data',
    verify='/path/to/ca-bundle.crt'
)

# ❌ DANGEROUS - Disable verification (NEVER in production)
response = requests.get('https://api.example.com/data', verify=False)
# This makes you vulnerable to MITM attacks!

# ✅ SAFE - With timeout (prevent hanging)
response = requests.get(
    'https://api.example.com/data',
    timeout=10,
    verify=True
)
```

### aiohttp Async Client

```python
# ✅ SAFE - aiohttp with certificate verification
import aiohttp
import ssl

async def fetch_data():
    # Default SSL context (verifies certificates)
    async with aiohttp.ClientSession() as session:
        async with session.get('https://api.example.com/data') as response:
            return await response.json()

# ✅ SAFE - Custom SSL context
async def fetch_with_custom_ssl():
    ssl_context = ssl.create_default_context()

    async with aiohttp.ClientSession(
        connector=aiohttp.TCPConnector(ssl=ssl_context)
    ) as session:
        async with session.get('https://api.example.com/data') as response:
            return await response.json()
```

### Flask/Django HTTPS Enforcement

```python
# ✅ Flask - Force HTTPS
from flask import Flask, redirect, request

app = Flask(__name__)

@app.before_request
def force_https():
    if not request.is_secure and not app.debug:
        url = request.url.replace('http://', 'https://', 1)
        return redirect(url, code=301)

# ✅ Flask - Security headers
@app.after_request
def add_security_headers(response):
    # Force HTTPS for 1 year
    response.headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
    return response

# ✅ Django - HTTPS settings (settings.py)
SECURE_SSL_REDIRECT = True  # Redirect HTTP to HTTPS
SECURE_HSTS_SECONDS = 31536000  # HSTS for 1 year
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True
SESSION_COOKIE_SECURE = True  # Only send cookies over HTTPS
CSRF_COOKIE_SECURE = True
```

**Best Practices:**

- Always use `verify=True` in requests (default)
- Never disable certificate verification in production
- Use HSTS headers to enforce HTTPS
- Set `secure` flag on cookies
- Use modern TLS versions (1.2+, preferably 1.3)
- Implement certificate pinning for high-security applications

---

## 11. Security Headers (Web Applications)

### Overview: Defense-in-Depth with Headers

Security headers provide defense-in-depth protection against various attacks.

**Official Source:** OWASP Secure Headers Project (<https://owasp.org/www-project-secure-headers/>)

### Flask Implementation

```python
from flask import Flask

app = Flask(__name__)

@app.after_request
def add_security_headers(response):
    # Prevent clickjacking
    response.headers['X-Frame-Options'] = 'DENY'

    # Prevent MIME type sniffing
    response.headers['X-Content-Type-Options'] = 'nosniff'

    # Enable browser XSS protection
    response.headers['X-XSS-Protection'] = '1; mode=block'

    # Force HTTPS
    response.headers['Strict-Transport-Security'] = (
        'max-age=31536000; includeSubDomains; preload'
    )

    # Content Security Policy
    response.headers['Content-Security-Policy'] = (
        "default-src 'self'; "
        "script-src 'self'; "
        "style-src 'self' 'unsafe-inline'; "
        "img-src 'self' data: https:; "
        "font-src 'self'; "
        "connect-src 'self'; "
        "frame-ancestors 'none'; "
        "base-uri 'self'; "
        "form-action 'self'"
    )

    # Referrer policy
    response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'

    # Permissions policy
    response.headers['Permissions-Policy'] = (
        'geolocation=(), microphone=(), camera=()'
    )

    return response
```

### Django Middleware

```python
# middleware/security_headers.py
class SecurityHeadersMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)

        response['X-Frame-Options'] = 'DENY'
        response['X-Content-Type-Options'] = 'nosniff'
        response['X-XSS-Protection'] = '1; mode=block'
        response['Strict-Transport-Security'] = (
            'max-age=31536000; includeSubDomains; preload'
        )
        response['Content-Security-Policy'] = (
            "default-src 'self'; "
            "script-src 'self'; "
            "style-src 'self' 'unsafe-inline'"
        )
        response['Referrer-Policy'] = 'strict-origin-when-cross-origin'

        return response

# settings.py
MIDDLEWARE = [
    'middleware.security_headers.SecurityHeadersMiddleware',
    # ... other middleware
]
```

### FastAPI Implementation

```python
from fastapi import FastAPI
from starlette.middleware.base import BaseHTTPMiddleware

class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        response = await call_next(request)

        response.headers['X-Frame-Options'] = 'DENY'
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['X-XSS-Protection'] = '1; mode=block'
        response.headers['Strict-Transport-Security'] = (
            'max-age=31536000; includeSubDomains'
        )
        response.headers['Content-Security-Policy'] = (
            "default-src 'self'"
        )

        return response

app = FastAPI()
app.add_middleware(SecurityHeadersMiddleware)
```

---

## 12. Logging and Monitoring

### Overview: Security Event Logging

Log security events but never log sensitive data.

### Safe Logging Practices

```python
import logging

# ✅ Configure structured logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger(__name__)

# ✅ Log security events
def login_attempt(username, success):
    if success:
        logger.info(f"Successful login for user: {username}")
    else:
        logger.warning(f"Failed login attempt for user: {username}")

# ✅ Log with context
def api_access(user_id, endpoint, ip_address):
    logger.info(
        f"API access - User: {user_id}, Endpoint: {endpoint}, IP: {ip_address}"
    )

# ❌ NEVER log sensitive data
def bad_logging(username, password, credit_card):
    # NEVER DO THIS!
    logger.info(f"Login: {username}, Password: {password}")
    logger.info(f"Payment: Card {credit_card}")
```

### Structured Logging with python-json-logger

```python
from pythonjsonlogger import jsonlogger
import logging

# ✅ JSON structured logging
logHandler = logging.StreamHandler()
formatter = jsonlogger.JsonFormatter()
logHandler.setFormatter(formatter)

logger = logging.getLogger()
logger.addHandler(logHandler)
logger.setLevel(logging.INFO)

# Usage
logger.info("User login", extra={
    'user_id': user_id,
    'ip_address': request.remote_addr,
    'user_agent': request.headers.get('User-Agent'),
    'success': True
})
```

**Best Practices:**

- Log authentication events (success and failure)
- Log authorization failures
- Log input validation failures
- Log security exceptions
- NEVER log passwords, API keys, tokens, credit cards
- Use structured logging (JSON) for analysis
- Implement log rotation and retention
- Monitor logs for suspicious patterns

---

## 13. Rate Limiting

### Overview: Brute Force Protection

Prevent brute force attacks and API abuse with rate limiting.

### Flask-Limiter

```python
# ✅ Flask rate limiting
from flask import Flask
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

app = Flask(__name__)
limiter = Limiter(
    app=app,
    key_func=get_remote_address,
    default_limits=["200 per day", "50 per hour"],
    storage_uri="redis://localhost:6379"
)

@app.route("/api/data")
@limiter.limit("10 per minute")
def api_endpoint():
    return {"data": "value"}

@app.route("/login", methods=["POST"])
@limiter.limit("5 per minute")
def login():
    # Prevent brute force
    return {"status": "ok"}
```

### FastAPI - slowapi

```python
# ✅ FastAPI rate limiting
from fastapi import FastAPI, Request
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

limiter = Limiter(key_func=get_remote_address)
app = FastAPI()
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

@app.get("/api/data")
@limiter.limit("10/minute")
async def api_endpoint(request: Request):
    return {"data": "value"}

@app.post("/login")
@limiter.limit("5/minute")
async def login(request: Request):
    return {"status": "ok"}
```

**Best Practices:**

- Implement rate limiting on authentication endpoints
- Use stricter limits on expensive operations
- Store rate limit data in Redis for distributed systems
- Return 429 Too Many Requests status code
- Include Retry-After header in responses

---

## Summary Checklist

### Critical Security Practices

- [ ] Use parameterized queries for all database operations
- [ ] Never use `shell=True` with subprocess and user input
- [ ] Validate all input with Pydantic or similar
- [ ] Never hardcode secrets - use environment variables or secrets managers
- [ ] Scan dependencies weekly with pip-audit or Safety
- [ ] Never use pickle with untrusted data
- [ ] Use bcrypt or Argon2 for password hashing
- [ ] Use `secrets` module for random tokens (not `random`)
- [ ] Run Bandit security linter on every commit
- [ ] Always verify HTTPS certificates (never `verify=False`)
- [ ] Implement security headers (CSP, HSTS, X-Frame-Options)
- [ ] Log security events but never log sensitive data
- [ ] Implement rate limiting on authentication endpoints
- [ ] Use framework auto-escaping for XSS prevention
- [ ] Keep Python and all dependencies updated

### Additional Resources

- **OWASP Cheat Sheet Series:** <https://cheatsheetseries.owasp.org/>
- **Python Security Best Practices:** <https://python.readthedocs.io/en/stable/library/security_warnings.html>
- **Bandit Security Linter:** <https://bandit.readthedocs.io/>
- **Cryptography Library:** <https://cryptography.io/>
- **Pydantic Validation:** <https://docs.pydantic.dev/>
- **pip-audit:** <https://pypi.org/project/pip-audit/>
- **Safety:** <https://pypi.org/project/safety/>

---

**Document Version:** 1.0
**Last Updated:** 2025-01-17
**Maintained By:** Python skill reference documentation
