-- PriceDrop Diary / Project Check-in 2 (SQLite; Android Room compatible)
PRAGMA foreign_keys = ON;
DROP TABLE IF EXISTS PriceObservation;
DROP TABLE IF EXISTS Product;
DROP TABLE IF EXISTS Store;
DROP TABLE IF EXISTS Category;

CREATE TABLE Category (
  category_id INTEGER PRIMARY KEY,
  category_name TEXT NOT NULL UNIQUE
);
CREATE TABLE Product (
  product_id INTEGER PRIMARY KEY,
  product_name TEXT NOT NULL,
  category_id INTEGER,
  target_price NUMERIC CHECK (target_price IS NULL OR target_price > 0),
  FOREIGN KEY (category_id) REFERENCES Category(category_id) ON DELETE SET NULL
);
CREATE TABLE Store (
  store_id INTEGER PRIMARY KEY,
  store_name TEXT NOT NULL UNIQUE,
  is_online INTEGER NOT NULL DEFAULT 0 CHECK (is_online IN (0,1))
);
CREATE TABLE PriceObservation (
  obs_id INTEGER PRIMARY KEY,
  product_id INTEGER NOT NULL,
  store_id INTEGER NOT NULL,
  price NUMERIC NOT NULL CHECK (price > 0),
  observed_date TEXT NOT NULL CHECK (observed_date GLOB '????-??-??'),
  note TEXT,
  FOREIGN KEY (product_id) REFERENCES Product(product_id) ON DELETE CASCADE,
  FOREIGN KEY (store_id) REFERENCES Store(store_id) ON DELETE CASCADE,
  UNIQUE(product_id,store_id,observed_date)
);
CREATE INDEX idx_observation_product_store_date ON PriceObservation(product_id,store_id,observed_date DESC);
INSERT INTO Category VALUES (1,'Electronics'),(2,'Apparel'),(3,'Kitchen');
INSERT INTO Product VALUES
  (1,'Noise-Cancelling Headphones',1,250.00),
  (2,'Running Shoes',2,90.00),
  (3,'Espresso Grinder',3,NULL);
INSERT INTO Store VALUES (1,'Amazon',1),(2,'Best Buy',0),(3,'Target',0);
INSERT INTO PriceObservation(obs_id,product_id,store_id,price,observed_date,note) VALUES
  (1,1,1,299.99,'2026-09-01',NULL),
  (2,1,2,279.99,'2026-09-15',NULL),
  (3,1,1,249.99,'2026-10-01',NULL),
  (4,2,3,110.00,'2026-09-10',NULL),
  (5,2,3,89.99,'2026-10-02',NULL),
  (6,2,1,95.00,'2026-10-02',NULL);

-- Check 1: product category filter (preserves Check-in 1 behavior)
SELECT p.product_name,c.category_name,p.target_price
FROM Product p JOIN Category c ON p.category_id=c.category_id
WHERE c.category_name='Electronics';
-- Check 2: price history (including store names)
SELECT s.store_name,o.price,o.observed_date
FROM PriceObservation o JOIN Store s ON s.store_id=o.store_id
WHERE o.product_id=1 ORDER BY o.observed_date DESC;
-- Check 3: low, average, count (computed, never stored)
SELECT p.product_name,MIN(o.price) AS lowest_price,
  ROUND(AVG(o.price),2) AS average_price,COUNT(*) AS observations
FROM Product p JOIN PriceObservation o ON o.product_id=p.product_id
GROUP BY p.product_id,p.product_name;
-- Check 4: exact original smart buy rule: latest per product/store, target OR historical deal
WITH stats AS (
 SELECT product_id,MIN(price) AS low,AVG(price) AS avg_price,COUNT(*) AS n
 FROM PriceObservation GROUP BY product_id
), latest AS (
 SELECT o.* FROM PriceObservation o
 WHERE NOT EXISTS (SELECT 1 FROM PriceObservation newer
   WHERE newer.product_id=o.product_id AND newer.store_id=o.store_id
     AND newer.observed_date>o.observed_date)
)
SELECT p.product_name,s.store_name,l.price,
 CASE WHEN p.target_price IS NOT NULL AND l.price<=p.target_price
      THEN 'Target hit' ELSE 'Historical deal' END AS signal_reason
FROM latest l
JOIN Product p ON p.product_id=l.product_id
JOIN Store s ON s.store_id=l.store_id
JOIN stats t ON t.product_id=l.product_id
WHERE (p.target_price IS NOT NULL AND l.price<=p.target_price)
   OR (t.n>=3 AND l.price<=1.05*t.low AND l.price<t.avg_price)
ORDER BY p.product_id,s.store_id;
