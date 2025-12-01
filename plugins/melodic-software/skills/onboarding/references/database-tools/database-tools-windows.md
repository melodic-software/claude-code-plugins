# Database Tools Windows

For cross-platform database tool information (DBeaver features and comparisons), see [Database Tools](database-tools.md).

This guide covers **Windows-specific** installation and configuration.

**Last Verified:** 2025-11-11

---

## Overview

This guide covers essential database tools for Windows development:

- **SQL Server Management Studio (SSMS)** - Full-featured SQL Server administration (Windows-only)
- **DBeaver** - Free, open-source universal database tool

---

## SQL Server Management Studio (SSMS)

Microsoft's integrated environment for managing SQL Server infrastructure and databases.

**Official Documentation:** [Install SSMS - Microsoft Learn](https://learn.microsoft.com/en-us/ssms/install/install)

**Current Version:** SSMS 21 (as of 2025-01)

### What is SSMS?

SSMS is a free, Windows-only IDE for:

- Managing SQL Server 2014 and later
- Azure SQL Database
- Azure SQL Managed Instance
- Azure Synapse Analytics
- Microsoft Fabric

SSMS provides a graphical interface for configuring, monitoring, and administering SQL Server instances, as well as querying and editing T-SQL code.

### SSMS System Requirements

- **Operating System:** Windows 10/11 or Windows Server 2016+
- **Permissions:** Administrator access required
- **Storage:** Ensure adequate free disk space
- **Updates:** Apply latest Windows updates and restart before installation

For detailed system requirements, see the [official documentation](https://learn.microsoft.com/en-us/ssms/install/install).

### SSMS Installation

#### 1. Download SSMS

Download the stub installer:

**[Download SSMS 21](https://aka.ms/ssms/21/release/vs_SSMS.exe)**

This downloads `vs_SSMS.exe`, which launches the Visual Studio Installer.

> **Note:** SSMS 21 no longer provides a standalone MSI installer. Installation is handled through the Visual Studio Installer.

#### 2. Run the Installer

1. Locate `vs_SSMS.exe` in your Downloads folder
2. Right-click and select **Run as administrator**
3. If prompted by User Account Control, click **Yes**

#### 3. Accept Terms

When the Visual Studio Installer opens:

1. Review the privacy statement and license terms
2. Click **Continue** to accept

#### 4. Select Workloads (Optional)

The installer allows you to add optional workloads:

- **Hybrid and Migration tools** - For database migration scenarios
- Other Visual Studio components (if needed)

For a basic SSMS installation, you can skip this and proceed directly to installation.

#### 5. Select Individual Components (Optional)

For granular control, you can select specific components. Most users can skip this step.

#### 6. Choose Language Packs (Optional)

SSMS supports 14 language locales. English is installed by default.

To add additional languages, select them from the language pack list.

#### 7. Select Installation Location (Optional)

You can change the installation drive location:

- This option is only available on **first-time installation**
- Default location is typically `C:\Program Files (x86)\Microsoft SQL Server Management Studio 21`

#### 8. Complete Installation

1. Click **Install** to begin
2. Wait for the installation to complete (this may take several minutes)
3. Click **Launch** when installation finishes

#### 9. Sign In (Optional)

You can sign in with a Microsoft account to synchronize settings across devices. This step is optional.

### Verify SSMS Installation

After installation, verify SSMS is working:

#### 1. Launch SSMS

- Open Start menu
- Search for **SQL Server Management Studio 21**
- Click to launch

#### 2. Check Version

1. Open SSMS
2. Go to **Help** > **About Microsoft SQL Server Management Studio**
3. Verify version shows **21.x**

#### 3. Test Connection (Optional)

If you have a SQL Server instance available:

1. In the **Connect to Server** dialog, enter your server details
2. Click **Connect**
3. Verify you can connect successfully

### SSMS Troubleshooting

**Installation Fails:**

- Ensure you have administrator permissions
- Apply all Windows updates and restart
- Check available disk space
- Review the [official troubleshooting guide](https://learn.microsoft.com/en-us/ssms/install/install)

**Known Issues:**

- Check the [SSMS Developer Community](https://developercommunity.visualstudio.com/search?space=62) for reported issues

**Previous Versions:**

- If you need to install an older version, see [Previous SSMS releases](https://learn.microsoft.com/en-us/sql/ssms/release-notes-ssms)

### SSMS Resources

- [SSMS Documentation](https://learn.microsoft.com/en-us/sql/ssms/)
- [What's New in SSMS 21](https://learn.microsoft.com/en-us/sql/ssms/release-notes-ssms)

---

## Other Database Tools

### DBeaver (Community Edition)

Free, open-source universal database tool supporting MySQL, PostgreSQL, SQL Server, Oracle, and more.

**Website:** [https://dbeaver.io/](https://dbeaver.io/)

### SQL Server Developer Edition

Free, full-featured edition of SQL Server for development and testing.

**Download:** [SQL Server Downloads](https://www.microsoft.com/en-us/sql-server/sql-server-downloads)

### LocalDB

Lightweight version of SQL Server Express for developers.

**Documentation:** [SQL Server Express LocalDB](https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/sql-server-express-localdb)
