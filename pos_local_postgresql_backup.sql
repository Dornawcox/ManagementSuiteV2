-- ============================================================================
-- FARM STORE POS - LOCAL POSTGRESQL SCHEMA
-- For Raspberry Pi or similar local hosting
-- 
-- This schema is compatible with standard PostgreSQL 12+
-- No Supabase-specific features (RLS policies are included but optional)
-- ============================================================================

-- IMPORTANT: Run this as a superuser or the database owner
-- Example: psql -U postgres -d farm_pos -f pos_local_postgresql_backup.sql

-- ============================================================================
-- SETUP
-- ============================================================================

-- Enable UUID extension (required for transaction IDs)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- DROP EXISTING (for clean reinstall - comment out to preserve data)
-- ============================================================================

DROP TABLE IF EXISTS pos_transaction_items CASCADE;
DROP TABLE IF EXISTS pos_transactions CASCADE;
DROP TABLE IF EXISTS pos_settlements CASCADE;
DROP TABLE IF EXISTS pos_products CASCADE;
DROP TABLE IF EXISTS pos_categories CASCADE;
DROP TABLE IF EXISTS pos_vendors CASCADE;
DROP TABLE IF EXISTS pos_devices CASCADE;
DROP TABLE IF EXISTS pos_settings CASCADE;

DROP TYPE IF EXISTS pos_vendor_type CASCADE;
DROP TYPE IF EXISTS pos_unit_type CASCADE;
DROP TYPE IF EXISTS pos_payment_method CASCADE;
DROP TYPE IF EXISTS pos_device_type CASCADE;

-- ============================================================================
-- CUSTOM ENUM TYPES
-- ============================================================================

CREATE TYPE pos_vendor_type AS ENUM ('owner', 'consignment');
CREATE TYPE pos_unit_type AS ENUM ('each', 'weight', 'bunch', 'dozen', 'half-dozen', 'pint', 'gallon');
CREATE TYPE pos_payment_method AS ENUM ('cash', 'card', 'check', 'account');
CREATE TYPE pos_device_type AS ENUM ('scanner', 'printer', 'scale', 'cashDrawer', 'cardReader', 'labelPrinter', 'customerDisplay');

-- ============================================================================
-- TABLES
-- ============================================================================

-- Vendors (farm owner and consignment partners)
CREATE TABLE pos_vendors (
  id              TEXT PRIMARY KEY,
  name            TEXT NOT NULL,
  vendor_type     pos_vendor_type NOT NULL DEFAULT 'consignment',
  commission_rate DECIMAL(5,2) NOT NULL DEFAULT 15.00,
  contact_email   TEXT,
  contact_phone   TEXT,
  payment_method  TEXT DEFAULT 'check',
  payment_terms   TEXT DEFAULT 'net-15',
  color           TEXT DEFAULT '#666666',
  is_active       BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE pos_vendors IS 'Vendors supplying products - includes farm owner and consignment partners';
COMMENT ON COLUMN pos_vendors.vendor_type IS 'owner = farm products (0% commission), consignment = partner products';
COMMENT ON COLUMN pos_vendors.commission_rate IS 'Percentage of sales retained by farm for consignment vendors';

-- Product categories
CREATE TABLE pos_categories (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  icon        TEXT,
  is_active   BOOLEAN NOT NULL DEFAULT true
);

COMMENT ON TABLE pos_categories IS 'Product categories for POS display organization';

-- Products
CREATE TABLE pos_products (
  id            TEXT PRIMARY KEY DEFAULT 'p_' || substr(md5(random()::text), 1, 8),
  name          TEXT NOT NULL,
  price         DECIMAL(10,2) NOT NULL,
  unit          TEXT NOT NULL DEFAULT 'each',
  unit_type     pos_unit_type NOT NULL DEFAULT 'each',
  stock         INTEGER NOT NULL DEFAULT 0,
  min_stock     INTEGER NOT NULL DEFAULT 5,
  barcode       TEXT,
  image_url     TEXT,
  vendor_id     TEXT NOT NULL REFERENCES pos_vendors(id) ON DELETE RESTRICT,
  category_id   TEXT NOT NULL REFERENCES pos_categories(id) ON DELETE RESTRICT,
  farmos_asset  TEXT,
  is_active     BOOLEAN NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE pos_products IS 'Products available for sale in the farm store';
COMMENT ON COLUMN pos_products.unit_type IS 'Determines how product is sold - by weight, each, bunch, etc.';
COMMENT ON COLUMN pos_products.farmos_asset IS 'Optional link to farmOS asset for inventory sync';

CREATE INDEX pos_products_vendor ON pos_products(vendor_id);
CREATE INDEX pos_products_category ON pos_products(category_id);
CREATE INDEX pos_products_barcode ON pos_products(barcode) WHERE barcode IS NOT NULL;
CREATE INDEX pos_products_active ON pos_products(is_active) WHERE is_active = true;

-- Transactions (sales)
CREATE TABLE pos_transactions (
  id              UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  transaction_num TEXT NOT NULL,
  cashier_id      TEXT,
  subtotal        DECIMAL(10,2) NOT NULL,
  tax_amount      DECIMAL(10,2) NOT NULL DEFAULT 0,
  total           DECIMAL(10,2) NOT NULL,
  payment_method  pos_payment_method NOT NULL DEFAULT 'cash',
  payment_ref     TEXT,
  status          TEXT NOT NULL DEFAULT 'completed',
  is_kiosk        BOOLEAN NOT NULL DEFAULT false,
  device_id       TEXT,
  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE pos_transactions IS 'Completed sales transactions';
COMMENT ON COLUMN pos_transactions.is_kiosk IS 'True if transaction was self-service kiosk';

CREATE INDEX pos_transactions_date ON pos_transactions(created_at);
CREATE INDEX pos_transactions_status ON pos_transactions(status);
CREATE INDEX pos_transactions_num ON pos_transactions(transaction_num);

-- Transaction line items
CREATE TABLE pos_transaction_items (
  id              UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  transaction_id  UUID NOT NULL REFERENCES pos_transactions(id) ON DELETE CASCADE,
  product_id      TEXT NOT NULL REFERENCES pos_products(id) ON DELETE RESTRICT,
  vendor_id       TEXT NOT NULL REFERENCES pos_vendors(id) ON DELETE RESTRICT,
  quantity        DECIMAL(10,3) NOT NULL,
  unit_price      DECIMAL(10,2) NOT NULL,
  line_total      DECIMAL(10,2) NOT NULL,
  commission_rate DECIMAL(5,2) NOT NULL,
  commission_amt  DECIMAL(10,2) NOT NULL,
  is_weight       BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE pos_transaction_items IS 'Individual items in each transaction';
COMMENT ON COLUMN pos_transaction_items.commission_amt IS 'Calculated commission amount for this line item';

CREATE INDEX pos_items_transaction ON pos_transaction_items(transaction_id);
CREATE INDEX pos_items_vendor ON pos_transaction_items(vendor_id);
CREATE INDEX pos_items_product ON pos_transaction_items(product_id);

-- Vendor settlements (payouts)
CREATE TABLE pos_settlements (
  id            UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  vendor_id     TEXT NOT NULL REFERENCES pos_vendors(id) ON DELETE RESTRICT,
  period_start  DATE NOT NULL,
  period_end    DATE NOT NULL,
  gross_sales   DECIMAL(10,2) NOT NULL,
  commission    DECIMAL(10,2) NOT NULL,
  net_payable   DECIMAL(10,2) NOT NULL,
  status        TEXT NOT NULL DEFAULT 'pending',
  paid_at       TIMESTAMPTZ,
  paid_by       TEXT,
  payment_ref   TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE pos_settlements IS 'Vendor payout records for consignment sales';

CREATE INDEX pos_settlements_vendor ON pos_settlements(vendor_id);
CREATE INDEX pos_settlements_status ON pos_settlements(status);
CREATE INDEX pos_settlements_period ON pos_settlements(period_start, period_end);

-- Peripheral devices
CREATE TABLE pos_devices (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  device_type pos_device_type NOT NULL,
  model       TEXT,
  connection  TEXT NOT NULL DEFAULT 'usb',
  port        TEXT,
  status      TEXT NOT NULL DEFAULT 'disconnected',
  is_enabled  BOOLEAN NOT NULL DEFAULT true,
  config      JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE pos_devices IS 'POS peripheral devices - scanners, printers, scales, etc.';

-- Settings (key-value store)
CREATE TABLE pos_settings (
  key         TEXT PRIMARY KEY,
  value       JSONB NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE pos_settings IS 'Application settings stored as key-value JSONB pairs';

-- ============================================================================
-- DEFAULT DATA
-- ============================================================================

-- Default categories
INSERT INTO pos_categories (id, name, sort_order, icon) VALUES
  ('vegetables', 'Vegetables', 1, '🥬'),
  ('fruit', 'Fruit', 2, '🍎'),
  ('eggs', 'Eggs', 3, '🥚'),
  ('dairy', 'Dairy', 4, '🧀'),
  ('meat', 'Meat', 5, '🥩'),
  ('preserves', 'Preserves', 6, '🍯');

-- Default settings
INSERT INTO pos_settings (key, value) VALUES
  ('store', '{"name": "Farm Cooperative", "address": "123 Farm Road", "phone": "(555) 123-4567", "email": "store@farm.local"}'::jsonb),
  ('tax', '{"rate": 0, "enabled": false}'::jsonb),
  ('kiosk', '{"enabled": true, "timeout": 60}'::jsonb),
  ('receipt', '{"header": "Thank you for shopping local!", "footer": "Support your local farmers"}'::jsonb),
  ('payment', '{"processor": "stripe", "testMode": true}'::jsonb);

-- ============================================================================
-- ROW LEVEL SECURITY (Optional - Enable for multi-user access control)
-- ============================================================================

-- Uncomment these lines to enable RLS (requires authentication setup)
/*
ALTER TABLE pos_vendors ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_transaction_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_categories ENABLE ROW LEVEL SECURITY;

-- Allow all access (adjust for your security requirements)
CREATE POLICY "allow_all_vendors" ON pos_vendors FOR ALL USING (true);
CREATE POLICY "allow_all_products" ON pos_products FOR ALL USING (true);
CREATE POLICY "allow_all_transactions" ON pos_transactions FOR ALL USING (true);
CREATE POLICY "allow_all_items" ON pos_transaction_items FOR ALL USING (true);
CREATE POLICY "allow_all_settlements" ON pos_settlements FOR ALL USING (true);
CREATE POLICY "allow_all_devices" ON pos_devices FOR ALL USING (true);
CREATE POLICY "allow_all_settings" ON pos_settings FOR ALL USING (true);
CREATE POLICY "allow_all_categories" ON pos_categories FOR ALL USING (true);
*/

-- ============================================================================
-- TRIGGERS (Auto-update timestamps)
-- ============================================================================

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_vendors_timestamp
  BEFORE UPDATE ON pos_vendors
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_products_timestamp
  BEFORE UPDATE ON pos_products
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_settings_timestamp
  BEFORE UPDATE ON pos_settings
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================================
-- USEFUL VIEWS
-- ============================================================================

-- Sales summary by vendor
CREATE OR REPLACE VIEW pos_vendor_sales_summary AS
SELECT 
  v.id as vendor_id,
  v.name as vendor_name,
  v.vendor_type,
  v.commission_rate,
  COALESCE(SUM(ti.line_total), 0) as total_sales,
  COALESCE(SUM(ti.commission_amt), 0) as total_commission,
  COALESCE(SUM(ti.line_total) - SUM(ti.commission_amt), 0) as net_payable,
  COUNT(DISTINCT ti.transaction_id) as transaction_count,
  COUNT(ti.id) as items_sold
FROM pos_vendors v
LEFT JOIN pos_transaction_items ti ON v.id = ti.vendor_id
LEFT JOIN pos_transactions t ON ti.transaction_id = t.id AND t.status = 'completed'
GROUP BY v.id, v.name, v.vendor_type, v.commission_rate;

-- Daily sales summary
CREATE OR REPLACE VIEW pos_daily_sales AS
SELECT 
  DATE(created_at) as sale_date,
  COUNT(*) as transaction_count,
  SUM(subtotal) as subtotal,
  SUM(tax_amount) as tax,
  SUM(total) as total,
  SUM(CASE WHEN payment_method = 'cash' THEN total ELSE 0 END) as cash_total,
  SUM(CASE WHEN payment_method = 'card' THEN total ELSE 0 END) as card_total
FROM pos_transactions
WHERE status = 'completed'
GROUP BY DATE(created_at)
ORDER BY sale_date DESC;

-- Low stock products
CREATE OR REPLACE VIEW pos_low_stock AS
SELECT 
  p.id,
  p.name,
  p.stock,
  p.min_stock,
  p.unit,
  v.name as vendor_name,
  c.name as category_name
FROM pos_products p
JOIN pos_vendors v ON p.vendor_id = v.id
JOIN pos_categories c ON p.category_id = c.id
WHERE p.is_active = true 
  AND p.stock <= p.min_stock
ORDER BY p.stock ASC;

-- ============================================================================
-- DEMO DATA (Optional - Remove for production)
-- ============================================================================

-- Demo vendors
INSERT INTO pos_vendors (id, name, vendor_type, commission_rate, color, contact_email) VALUES
  ('tuckaway-farm', 'Tuckaway Farm', 'owner', 0, '#16a34a', 'farm@tuckaway.com'),
  ('sunshine-eggs', 'Sunshine Eggs', 'consignment', 15, '#eab308', 'eggs@sunshine.com'),
  ('valley-dairy', 'Valley Dairy', 'consignment', 12, '#3b82f6', 'info@valleydairy.com'),
  ('wildwood-preserves', 'Wildwood Preserves', 'consignment', 20, '#dc2626', 'jams@wildwood.com'),
  ('green-meadow-meats', 'Green Meadow Meats', 'consignment', 18, '#7c3aed', 'orders@greenmeadow.com')
ON CONFLICT (id) DO NOTHING;

-- Demo products
INSERT INTO pos_products (id, name, price, unit, unit_type, stock, category_id, vendor_id, barcode, image_url) VALUES
  ('p_tomatoes', 'Heirloom Tomatoes', 4.99, 'lb', 'weight', 50, 'vegetables', 'tuckaway-farm', 'VEG-10001', 'https://images.unsplash.com/photo-1546470427-227c7369a9b9?w=300&h=300&fit=crop'),
  ('p_lettuce', 'Butterhead Lettuce', 3.50, 'head', 'each', 30, 'vegetables', 'tuckaway-farm', 'VEG-10002', 'https://images.unsplash.com/photo-1622206151226-18ca2c9ab4a1?w=300&h=300&fit=crop'),
  ('p_carrots', 'Rainbow Carrots', 3.99, 'bunch', 'bunch', 40, 'vegetables', 'tuckaway-farm', 'VEG-10003', 'https://images.unsplash.com/photo-1598170845058-32b9d6a5da37?w=300&h=300&fit=crop'),
  ('p_kale', 'Tuscan Kale', 4.50, 'bunch', 'bunch', 25, 'vegetables', 'tuckaway-farm', 'VEG-10004', 'https://images.unsplash.com/photo-1524179091875-bf99a9a6af57?w=300&h=300&fit=crop'),
  ('p_apples', 'Honeycrisp Apples', 3.99, 'lb', 'weight', 100, 'fruit', 'tuckaway-farm', 'FRU-20001', 'https://images.unsplash.com/photo-1560806887-1e4cd0b6cbd6?w=300&h=300&fit=crop'),
  ('p_peaches', 'Georgia Peaches', 4.99, 'lb', 'weight', 60, 'fruit', 'tuckaway-farm', 'FRU-20002', 'https://images.unsplash.com/photo-1595124442225-71e5bdf82930?w=300&h=300&fit=crop'),
  ('p_eggs_dozen', 'Farm Fresh Eggs (Dozen)', 6.99, 'dozen', 'dozen', 40, 'eggs', 'sunshine-eggs', 'EGG-30001', 'https://images.unsplash.com/photo-1582722872445-44dc5f7e3c8f?w=300&h=300&fit=crop'),
  ('p_eggs_half', 'Farm Fresh Eggs (Half Dozen)', 3.99, 'half-dozen', 'half-dozen', 30, 'eggs', 'sunshine-eggs', 'EGG-30002', 'https://images.unsplash.com/photo-1598965675045-45c5e72c7d05?w=300&h=300&fit=crop'),
  ('p_milk', 'Whole Milk (Gallon)', 7.99, 'gallon', 'gallon', 20, 'dairy', 'valley-dairy', 'DAI-40001', 'https://images.unsplash.com/photo-1563636619-e9143da7973b?w=300&h=300&fit=crop'),
  ('p_cheese', 'Aged Cheddar', 8.99, 'each', 'each', 15, 'dairy', 'valley-dairy', 'DAI-40002', 'https://images.unsplash.com/photo-1618164436241-4473940d1f5c?w=300&h=300&fit=crop'),
  ('p_butter', 'Cultured Butter', 6.50, 'each', 'each', 25, 'dairy', 'valley-dairy', 'DAI-40003', 'https://images.unsplash.com/photo-1589985270826-4b7bb135bc9d?w=300&h=300&fit=crop'),
  ('p_bacon', 'Smoked Bacon', 12.99, 'each', 'each', 20, 'meat', 'green-meadow-meats', 'MEA-50001', 'https://images.unsplash.com/photo-1606851091851-e8c8c0fca5ba?w=300&h=300&fit=crop'),
  ('p_sausage', 'Breakfast Sausage', 9.99, 'each', 'each', 25, 'meat', 'green-meadow-meats', 'MEA-50002', 'https://images.unsplash.com/photo-1432139555190-58524dae6a55?w=300&h=300&fit=crop'),
  ('p_jam', 'Strawberry Jam', 7.99, 'jar', 'each', 30, 'preserves', 'wildwood-preserves', 'PRE-60001', 'https://images.unsplash.com/photo-1563805042-7684c019e1cb?w=300&h=300&fit=crop'),
  ('p_honey', 'Wildflower Honey', 12.99, 'jar', 'each', 20, 'preserves', 'wildwood-preserves', 'PRE-60002', 'https://images.unsplash.com/photo-1587049352846-4a222e784d38?w=300&h=300&fit=crop'),
  ('p_pickles', 'Dill Pickles', 6.99, 'jar', 'each', 25, 'preserves', 'wildwood-preserves', 'PRE-60003', 'https://images.unsplash.com/photo-1595295546866-d8cd5a7c1b86?w=300&h=300&fit=crop')
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- VERIFICATION
-- ============================================================================

SELECT 'POS Schema installed successfully!' as status;

SELECT 'Tables created:' as info;
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'public' AND table_name LIKE 'pos_%' 
ORDER BY table_name;

SELECT 'Views created:' as info;
SELECT table_name as view_name FROM information_schema.views 
WHERE table_schema = 'public' AND table_name LIKE 'pos_%';

SELECT 'Record counts:' as info;
SELECT 'Vendors' as table_name, COUNT(*) as count FROM pos_vendors
UNION ALL SELECT 'Categories', COUNT(*) FROM pos_categories
UNION ALL SELECT 'Products', COUNT(*) FROM pos_products
UNION ALL SELECT 'Settings', COUNT(*) FROM pos_settings;
