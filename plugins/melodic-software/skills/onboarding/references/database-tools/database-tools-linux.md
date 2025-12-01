# Database Tools Linux

For cross-platform database tool information (DBeaver features and comparisons), see [Database Tools](database-tools.md).

This guide covers **Linux-specific** installation and configuration.

**Last Verified:** 2025-11-11

---

## Overview

SQL Server Management Studio (SSMS) is **Windows-only** and not available for Linux. This guide covers cross-platform alternatives for Linux users.

---

## DBeaver (Community Edition)

Free, open-source universal database tool supporting SQL Server, MySQL, PostgreSQL, Oracle, and more.

**Website:** [https://dbeaver.io/](https://dbeaver.io/)

### DBeaver Features

- Support for 80+ databases
- ER diagrams
- Data export/import
- SQL editor with auto-completion
- Visual query builder
- Database metadata exploration

### DBeaver Installation

#### Debian/Ubuntu

```bash
# Download the .deb package
wget https://dbeaver.io/files/dbeaver-ce_latest_amd64.deb

# Install
sudo dpkg -i dbeaver-ce_latest_amd64.deb

# Install dependencies
sudo apt-get install -f
```

#### Via Snap

```bash
sudo snap install dbeaver-ce
```

#### Manual Download

Download the appropriate package from [dbeaver.io/download](https://dbeaver.io/download/).

---

## pgAdmin (PostgreSQL-specific)

Open-source administration and development platform for PostgreSQL.

**Website:** [https://www.pgadmin.org/](https://www.pgadmin.org/)

### pgAdmin Features

- Web-based and desktop modes
- Query tool with syntax highlighting
- Visual explain plans
- Database schema visualization
- Backup and restore tools

### pgAdmin Installation

#### Via Debian/Ubuntu Package

```bash
# Add repository
curl -fsS https://www.pgadmin.org/static/packages_pgadmin_org.pub | sudo gpg --dearmor -o /usr/share/keyrings/packages-pgadmin-org.gpg

sudo sh -c 'echo "deb [signed-by=/usr/share/keyrings/packages-pgadmin-org.gpg] https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/$(lsb_release -cs) pgadmin4 main" > /etc/apt/sources.list.d/pgadmin4.list'

# Update and install
sudo apt update
sudo apt install pgadmin4-desktop
```

---

## MySQL Workbench (MySQL-specific)

Official MySQL GUI tool for database design, development, and administration.

**Website:** [https://www.mysql.com/products/workbench/](https://www.mysql.com/products/workbench/)

### MySQL Workbench Features

- Visual database design
- SQL development
- Database administration
- Data migration
- Performance tuning

### MySQL Workbench Installation

#### Via apt Package

```bash
sudo apt update
sudo apt install mysql-workbench
```

#### Snap

```bash
sudo snap install mysql-workbench-community
```

---

## SQLite Browser

Lightweight, open-source tool for SQLite databases.

**Website:** [https://sqlitebrowser.org/](https://sqlitebrowser.org/)

### SQLite Browser Installation

#### Via apt Install

```bash
sudo apt update
sudo apt install sqlitebrowser
```

---

## Comparison: Database Tools for Linux

Since SSMS is not available on Linux, developers working with SQL Server on Linux should use alternative tools:

- **DBeaver** - Best for universal database support (SQL Server, MySQL, PostgreSQL, Oracle, etc.)
- **pgAdmin** - Best for PostgreSQL-specific administration
- **MySQL Workbench** - Best for MySQL-specific administration
- **SQLite Browser** - Best for SQLite database management
