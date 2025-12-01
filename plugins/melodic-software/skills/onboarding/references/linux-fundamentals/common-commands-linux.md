# Common Commands Linux

> This guide uses Ubuntu/Debian commands (WSL default). Callouts provided for other distros.

Essential Linux commands for day-to-day development work.

---

## Package Management

### Update System

```bash
sudo apt update && sudo apt upgrade -y
```

> **Other Distros:**
>
> - **Fedora/RHEL:** `sudo dnf upgrade`
> - **Arch:** `sudo pacman -Syu`

### Install Package

```bash
sudo apt install <package-name>
```

**Example:**

```bash
sudo apt install curl
```

> **Other Distros:**
>
> - **Fedora/RHEL:** `sudo dnf install <package-name>`
> - **Arch:** `sudo pacman -S <package-name>`

### Remove Package

```bash
sudo apt remove <package-name>
```

**Remove package and configuration files:**

```bash
sudo apt purge <package-name>
```

> **Other Distros:**
>
> - **Fedora/RHEL:** `sudo dnf remove <package-name>`
> - **Arch:** `sudo pacman -R <package-name>`

---

## File Operations

### List Files

```bash
ls          # List files
ls -la      # List all files (including hidden) with details
ls -lh      # List with human-readable file sizes
```

### Navigate Directories

```bash
cd /path/to/directory   # Change to specific directory
cd ..                   # Go up one level
cd ~                    # Go to home directory
cd -                    # Go to previous directory
pwd                     # Print working directory
```

### Create/Delete

```bash
mkdir dirname           # Create directory
mkdir -p path/to/dir    # Create nested directories
touch filename          # Create empty file
rm filename             # Remove file
rm -r dirname           # Remove directory recursively
rm -rf dirname          # Force remove directory (use carefully!)
```

### Copy/Move

```bash
cp source dest          # Copy file
cp -r source dest       # Copy directory recursively
mv source dest          # Move/rename file or directory
```

### View File Contents

```bash
cat filename            # Display entire file
less filename           # View file (scrollable)
head filename           # Show first 10 lines
tail filename           # Show last 10 lines
tail -f filename        # Follow file updates (e.g., logs)
```

---

## System Information

### OS and Kernel

```bash
uname -a                # All system information
uname -r                # Kernel version
lsb_release -a          # Distribution information (Ubuntu/Debian)
cat /etc/os-release     # OS information (universal)
```

### Hardware Information

```bash
lscpu                   # CPU information
free -h                 # Memory usage (human-readable)
df -h                   # Disk space usage
du -sh directory        # Directory size
lsblk                   # Block devices (disks)
```

### Network

```bash
ip addr                 # IP addresses
ip route                # Routing table
hostname                # System hostname
hostname -I             # IP address(es)
```

---

## Process Management

### View Processes

```bash
ps aux                  # All running processes
ps aux | grep process   # Find specific process
top                     # Interactive process viewer
htop                    # Enhanced process viewer (if installed)
```

### Manage Processes

```bash
kill <pid>              # Terminate process by PID
kill -9 <pid>           # Force kill process
killall <name>          # Kill all processes by name
pkill <pattern>         # Kill processes matching pattern
```

### Background Jobs

```bash
command &               # Run command in background
jobs                    # List background jobs
fg %1                   # Bring job 1 to foreground
bg %1                   # Resume job 1 in background
Ctrl+Z                  # Suspend current process
```

---

## Permissions

### View Permissions

```bash
ls -l filename          # View file permissions
ls -ld dirname          # View directory permissions
```

**Permission format:** `-rw-r--r--`

- First character: File type (`-` = file, `d` = directory, `l` = link)
- Next 9 characters: Permissions (owner, group, others)
  - `r` = read (4), `w` = write (2), `x` = execute (1)

### Change Permissions

```bash
chmod 755 filename      # rwxr-xr-x (owner: full, others: read+execute)
chmod 644 filename      # rw-r--r-- (owner: read+write, others: read)
chmod +x filename       # Add execute permission
chmod -w filename       # Remove write permission
```

### Change Ownership

```bash
chown user:group file   # Change owner and group
chown user file         # Change owner only
chown -R user:group dir # Change recursively
```

### Common Permission Patterns

```bash
chmod 755               # Executable files, directories
chmod 644               # Regular files
chmod 600               # Private files (SSH keys)
chmod 700               # Private executables/directories
```
