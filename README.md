# TF Management Suite

**FarmHack Management Suite** — A complete farm cooperative management system with multi-site authentication, document signing, media hosting, and point-of-sale for farm stores.

## 🚀 Quick Start

### GitHub Pages Deployment

1. Fork or clone this repository
2. Go to **Settings → Pages**
3. Set source to "Deploy from a branch" → select `main` / `root`
4. Your sites will be live at `https://yourusername.github.io/repo-name/`

### Local Development

```bash
# Simple Python server
python3 -m http.server 8080

# Then open: http://localhost:8080/Index.html
```

## 📁 File Structure

| File | Description |
|------|-------------|
| `Index.html` | Tuckaway Cooperative Riding Club portal |
| `farmhack-admin.html` | Admin panel — Supabase setup, members, POS config |
| `farm-pos-v4.html` | Farm Store POS system |
| `tuckaway-coop-barn.html` | Barn & cooperative management |
| `tuckaway-farm-hunters.html` | Hunter management portal |
| `wentworth-hunt-kennels.html` | Hunt kennel management |
| `supabase-schema.sql` | Database schema for Supabase |

## 🔧 Setup Guide

### 1. Create Supabase Project

1. Go to [supabase.com](https://supabase.com) and create a new project
2. Navigate to **Settings → API** and copy:
   - Project URL: `https://xxxxxx.supabase.co`
   - Anon/Public Key: `eyJhbG...`

### 2. Run Database Schema

1. In Supabase, go to **SQL Editor → New Query**
2. Copy contents of `supabase-schema.sql` and run
3. For POS functionality, also run the POS schema from the admin panel

### 3. Configure Sites

1. Open `farmhack-admin.html`
2. Enter your Supabase credentials on the **Credentials** page
3. Click **Save & Test Connection**
4. All sites share these credentials via localStorage

### 4. Configure Authentication

In Supabase **Authentication → URL Configuration**:
- Add your site URLs to **Redirect URLs**:
  - `https://yourusername.github.io/repo-name/Index.html`
  - `https://yourusername.github.io/repo-name/tuckaway-coop-barn.html`
  - etc.

## 🏪 Farm Store POS

The POS system supports:
- **Multi-vendor consignment** with configurable commission rates
- **Role-based access**: Admin, Manager, Cashier, Kiosk modes
- **Hardware integration**: Barcode scanners, receipt printers, scales, card readers
- **Payment processors**: Stripe, Square, SumUp, PayPal Zettle
- **farmOS integration**: Sync harvests and sales

### POS Login PINs (Demo Mode)
| Role | PIN | Access |
|------|-----|--------|
| Admin | 1234 | Full access |
| Manager | 5678 | Full access |
| Cashier | 0000 | POS only |
| Kiosk | 9999 | Self-service only |

## 🖥️ Self-Hosted / Raspberry Pi

For offline-first deployment on a Raspberry Pi 5:

1. Install Docker and Docker Compose
2. Deploy Supabase self-hosted (see admin panel → Self-Hosted Setup)
3. Configure local PostgreSQL for POS
4. Sites work offline with localStorage fallback

### Minimum Hardware
- Raspberry Pi 5 (8GB RAM)
- 1TB NVMe via PCIe HAT
- UPS for power protection
- Ethernet + WiFi

## 📱 Features by Site

### Barn / Coop (`Index.html`, `tuckaway-coop-barn.html`)
- Member directory and role management
- Liability waivers and document signing
- Boarding agreements
- Chore scheduling and logging

### Hunt Kennels (`wentworth-hunt-kennels.html`)
- Hound roster and health tracking
- Hunt event scheduling
- Member waivers and releases

### Hunters (`tuckaway-farm-hunters.html`)
- Hunter registration and check-in
- Stand assignments
- Hunt membership documents

### Farm Store POS (`farm-pos-v4.html`)
- Product catalog by category
- Multi-vendor inventory
- Transaction processing
- Vendor settlement reports

## 🔐 Security

- Row Level Security (RLS) on all tables
- Magic link authentication (no passwords)
- Role-based permissions (super_admin, admin, manager, member, guest)
- Per-site role overrides

## 📄 License

MIT License — See LICENSE file

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

---

Built with ❤️ for small farms and cooperatives
