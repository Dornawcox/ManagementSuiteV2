# Farm Store POS — Database Connection Guide

A complete guide for configuring the Farm Store POS system to connect to Supabase (cloud) or PostgreSQL (self-hosted on Raspberry Pi).

---

## Table of Contents

1. [Overview](#overview)
2. [Option A: Supabase Cloud Setup](#option-a-supabase-cloud-setup)
3. [Option B: PostgreSQL Self-Hosted Setup](#option-b-postgresql-self-hosted-setup)
4. [Using the Admin Tool](#using-the-admin-tool)
5. [POS Schema Installation](#pos-schema-installation)
6. [Testing the Connection](#testing-the-connection)
7. [Troubleshooting](#troubleshooting)

---

## Overview

The Farm Store POS system supports three database modes:

| Mode | Description | Best For |
|------|-------------|----------|
| **Demo** | No database, data in browser memory | Testing, demos |
| **Supabase** | Cloud-hosted PostgreSQL with auth | Quick setup, remote access |
| **PostgreSQL** | Self-hosted on Raspberry Pi | Offline-first, data sovereignty |

All configuration is done through the **FarmHack Admin** panel at `farmhack-admin.html`.

---

## Option A: Supabase Cloud Setup

### Step 1: Create Supabase Project

1. Go to [supabase.com](https://supabase.com) and sign up
2. Click **New Project**
3. Choose a name (e.g., "farm-cooperative")
4. Set a strong database password (save this!)
5. Select your region
6. Click **Create new project** (takes ~2 minutes)

### Step 2: Get API Credentials

1. In your project dashboard, go to **Settings → API**
2. Copy these values:
   - **Project URL**: `https://xxxxxx.supabase.co`
   - **anon/public key**: `eyJhbGciOi...` (safe for browsers)

> ⚠️ **Never use the `service_role` key in browser code** — it bypasses Row Level Security.

### Step 3: Configure in Admin Panel

1. Open `farmhack-admin.html`
2. Go to **🔑 Credentials** page
3. Paste your Project URL and Anon Key
4. Click **Save & Test Connection**

### Step 4: Run the Schema

1. In the Admin panel, go to **🏪 Farm Store POS**
2. Scroll to **📊 POS Schema**
3. Click **Copy POS SQL Schema**
4. In Supabase, go to **SQL Editor → New Query**
5. Paste the schema and click **Run**

### Step 5: Configure Authentication URLs

In Supabase **Authentication → URL Configuration**:

1. Add **Site URL**: Your main site (e.g., `https://yourname.github.io/farm-suite/`)
2. Add **Redirect URLs**:
   - `https://yourname.github.io/farm-suite/Index.html`
   - `https://yourname.github.io/farm-suite/farm-pos-v4.html`
   - `http://localhost:8080/Index.html` (for local dev)

---

## Option B: PostgreSQL Self-Hosted Setup

### Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| Device | Raspberry Pi 4 (4GB) | Raspberry Pi 5 (8GB) |
| Storage | 64GB SD card | 256GB+ NVMe via PCIe HAT |
| Power | Official PSU | UPS (CyberPower 425VA) |

### Step 1: Install PostgreSQL on Raspberry Pi

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install PostgreSQL
sudo apt install postgresql postgresql-contrib -y

# Start and enable service
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

### Step 2: Create Database and User

```bash
# Switch to postgres user
sudo -u postgres psql

# In PostgreSQL prompt:
CREATE DATABASE farm_pos;
CREATE USER pos_user WITH ENCRYPTED PASSWORD 'your_secure_password';
GRANT ALL PRIVILEGES ON DATABASE farm_pos TO pos_user;
\c farm_pos
GRANT ALL ON SCHEMA public TO pos_user;
\q
```

### Step 3: Configure Remote Access (Optional)

Edit PostgreSQL config to allow network connections:

```bash
# Edit postgresql.conf
sudo nano /etc/postgresql/15/main/postgresql.conf
# Change: listen_addresses = '*'

# Edit pg_hba.conf
sudo nano /etc/postgresql/15/main/pg_hba.conf
# Add line: host all all 192.168.0.0/24 scram-sha-256

# Restart PostgreSQL
sudo systemctl restart postgresql
```

### Step 4: Run the Schema

```bash
# Connect as pos_user
psql -h localhost -U pos_user -d farm_pos

# Paste the POS schema (from Admin panel → POS → Copy POS SQL Schema)
# Or run from file:
psql -h localhost -U pos_user -d farm_pos -f pos_schema.sql
```

### Step 5: Configure in Admin Panel

1. Open `farmhack-admin.html`
2. Go to **🏪 Farm Store POS**
3. Set **Database Backend** to "PostgreSQL (Self-Hosted)"
4. Enter connection details:
   - **Host**: `localhost` (or Pi's IP address)
   - **Port**: `5432`
   - **Database Name**: `farm_pos`
   - **Username**: `pos_user`
   - **Password**: Your password
5. Click **Save Configuration**

---

## Using the Admin Tool

### Opening the Admin Panel

Navigate to `farmhack-admin.html` in your browser. This works:
- From GitHub Pages
- From local file (`file://`)
- From local server (`python3 -m http.server 8080`)

### POS Configuration Page

Click **🏪 Farm Store POS** in the sidebar to access:

1. **Database Configuration**
   - Select backend (Demo/Supabase/PostgreSQL)
   - Enter connection credentials
   - Test connection

2. **Payment Processor**
   - Select provider (Stripe/Square/SumUp/PayPal/Cash)
   - Enter API keys (optional, can also be set in POS Admin)
   - Enable/disable test mode

3. **farmOS Integration**
   - Toggle sync for harvests → inventory
   - Toggle sync for sales → farmOS observations

4. **POS Schema**
   - Copy SQL to run in your database
   - View the complete schema

5. **Launch POS**
   - Quick link to open the POS system

### Where Settings Are Stored

| Setting | Storage | Key |
|---------|---------|-----|
| Supabase credentials | localStorage | `farmhack-supabase-v1` |
| POS configuration | localStorage | `farmhack-pos-config-v1` |
| User session | Supabase Auth | Managed by SDK |

All sites share these credentials via localStorage.

---

## POS Schema Installation

### Schema Overview

The POS system requires these tables:

| Table | Purpose |
|-------|---------|
| `pos_vendors` | Vendor/consigner records |
| `pos_categories` | Product categories |
| `pos_products` | Product catalog |
| `pos_transactions` | Sales transactions |
| `pos_transaction_items` | Line items per transaction |
| `pos_settlements` | Vendor payment settlements |
| `pos_devices` | Hardware device config |
| `pos_settings` | Store settings |

### Installing the Schema

**For Supabase:**

1. Admin Panel → 🏪 Farm Store POS → Copy POS SQL Schema
2. Supabase → SQL Editor → New Query → Paste → Run

**For PostgreSQL:**

```bash
# Save schema to file
# (copy from Admin panel)

# Run schema
psql -h localhost -U pos_user -d farm_pos -f pos_schema.sql
```

### Verifying Installation

In Supabase SQL Editor or psql:

```sql
-- Check tables exist
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'public' AND table_name LIKE 'pos_%';

-- Should return:
-- pos_vendors
-- pos_categories
-- pos_products
-- pos_transactions
-- pos_transaction_items
-- pos_settlements
-- pos_devices
-- pos_settings
```

---

## Testing the Connection

### From Admin Panel

1. Go to **🏪 Farm Store POS**
2. Click **Test Connection**
3. Expected results:
   - **Demo**: "Demo mode — no database required"
   - **Supabase**: "Supabase connected — POS tables found"
   - **PostgreSQL**: Configuration saved message

### From POS System

1. Open `farm-pos-v4.html`
2. Login as Admin (PIN: 1234)
3. Go to **⚙️ Admin → 🗄️ Database**
4. Click **Test Connection**
5. Check status indicator (green = connected)

### Manual Verification

**Supabase:**
```sql
SELECT COUNT(*) FROM pos_products;
SELECT COUNT(*) FROM pos_vendors;
```

**PostgreSQL:**
```bash
psql -h localhost -U pos_user -d farm_pos -c "SELECT COUNT(*) FROM pos_products;"
```

---

## Troubleshooting

### Common Issues

#### "Supabase not connected"

**Cause:** Credentials not saved or invalid.

**Fix:**
1. Go to Admin → Credentials
2. Verify Project URL format: `https://xxxxxx.supabase.co`
3. Verify Anon Key (starts with `eyJ`)
4. Click Save & Test

#### "POS tables not found"

**Cause:** Schema not installed.

**Fix:**
1. Admin → POS → Copy POS SQL Schema
2. Run in Supabase SQL Editor
3. Check for errors in the output

#### "Permission denied" errors

**Cause:** Row Level Security blocking access.

**Fix:**
1. Ensure you're authenticated (magic link)
2. Check RLS policies in Supabase
3. For testing, temporarily disable RLS:
   ```sql
   ALTER TABLE pos_products DISABLE ROW LEVEL SECURITY;
   ```

#### PostgreSQL "Connection refused"

**Cause:** PostgreSQL not running or not accepting connections.

**Fix:**
```bash
# Check service status
sudo systemctl status postgresql

# Check listening ports
sudo netstat -tlnp | grep 5432

# Check firewall
sudo ufw status
sudo ufw allow 5432/tcp  # if needed
```

#### "CORS error" in browser console

**Cause:** Cross-origin requests blocked.

**Fix:**
- For Supabase: Add your site to Authentication → URL Configuration
- For self-hosted: Configure CORS in your API layer

### Getting Help

1. Check browser console (F12) for detailed errors
2. Check Supabase logs: Dashboard → Logs
3. Check PostgreSQL logs: `/var/log/postgresql/`

### Reset Everything

To start fresh:

1. Clear browser localStorage:
   ```javascript
   localStorage.removeItem('farmhack-supabase-v1');
   localStorage.removeItem('farmhack-pos-config-v1');
   ```

2. Drop and recreate database:
   ```sql
   -- Supabase: Use the "Reset database" option in settings
   -- PostgreSQL:
   DROP DATABASE farm_pos;
   CREATE DATABASE farm_pos;
   ```

---

## Quick Reference

### Default Login PINs

| Role | PIN | Access |
|------|-----|--------|
| Admin | 1234 | Full system access |
| Manager | 5678 | Full except system config |
| Cashier | 0000 | POS transactions only |
| Kiosk | 9999 | Self-service mode only |

### Key URLs

| Resource | URL |
|----------|-----|
| Admin Panel | `farmhack-admin.html` |
| POS System | `farm-pos-v4.html` |
| Supabase Dashboard | `https://app.supabase.com` |

### Hardware Recommendations

| Device | Model | Price |
|--------|-------|-------|
| Scanner | Zebra DS2208 | $150 |
| Printer | Epson TM-T20III | $180 |
| Scale | Adam AZExtra 6 | $180 |
| Card Reader | Stripe M2 | $59 |

---

*Last updated: March 2026*
