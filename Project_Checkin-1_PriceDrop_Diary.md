# Project Check-in 1

## PRICEDROP DIARY: PRICE HISTORY TRACKER WITH SMART BUY SIGNAL

**Dev Raj Dhungana**
**WSU ID: N348Z294**

---

## 1. Problem Definition and Mobile Scope

### 1.1 Problem Definition

Shoppers who are waiting for a good deal on a specific item (headphones, shoes, a kitchen appliance) often cannot tell whether today's price is actually good. Prices differ from store to store and change often, and most people do not remember what they saw last week. Deal websites show the current price, but not the user's own price history for the items the user cares about.

Many people also do not know what a "good" price is for an item, so a single fixed target price is not enough. For this project, I plan to develop a mobile application called **PriceDrop Diary**. The application will let users record the prices they see for items they want, at different stores, and will learn what a good price is from the user's own logged history.

The main purpose of the application is to help users see how an item's price has changed, find the lowest and average price they have seen, and get a **buy-now signal** when the latest price at a store looks like a real deal.

### 1.2 Target Users and Platform

The application will be designed for individual shoppers. The target platform is **Android** (Kotlin with Jetpack Compose and a local SQLite database through Room). I will focus on Android instead of supporting both Android and iOS so that the project stays manageable during the semester. Mobile platform constraints that shape the design:

- **Offline-first:** all data is stored on the device, with no account or server.
- **Quick entry:** logging a price takes only a few taps (product, store, price), because users often log while standing in a store.
- **Local notifications:** the buy-now alert uses Android's local notification API, so no backend is needed.
- **No scraping:** prices are entered manually. Scraping store websites breaks easily, raises terms-of-service problems, and drains battery.
- **Lightweight computation:** the smart signal is plain SQL aggregation over a small local dataset, with no machine learning and no network use.

### 1.3 Application Scope

The main features I plan to include are:

- Add, view, edit, and delete a product, with an optional target price
- Assign a category to each product and filter the product list by category
- Add and manage stores (physical or online)
- Log a price observation (product, store, price, date, optional note)
- View the price history of a product, with store names
- View the lowest price, average price, and number of observations for a product
- Show a smart buy-now signal and send a local notification when it triggers

**Smart buy rule.** Only the *latest* price logged at each store counts. That price triggers Buy Now if it is either:

- **(a) Target hit:** at or below the user's target price, or
- **(b) Historical deal:** within 5% of the lowest price ever logged for that product *and* below its average logged price, with at least 3 observations for the product.

The buy-now signal, lowest price, and average price are calculated by queries instead of being stored in the database, so they always stay accurate as new prices are logged.

**Out of scope:** automatic price scraping, barcode scanning, social or deal-sharing features, affiliate links, cloud sync, and machine-learning price prediction. The scope emphasizes *personal* price tracking over deal-hunting community features.

---

## 2. Initial Database Design

For Check-in 1, I am starting with three tables: Product, Store, and PriceObservation. Product and Store are independent tables. PriceObservation connects them and holds the price data. I plan to review and normalize the design further in Check-in 2.

**Product**

| Column | Key | Description |
|---|---|---|
| product_id | Primary Key | Unique ID for a product |
| product_name | | Name of the product |
| category | | Product category (for example Electronics) |
| target_price | | Most the user wants to pay (NULL if no target set) |

**Store**

| Column | Key | Description |
|---|---|---|
| store_id | Primary Key | Unique ID for a store |
| store_name | | Name of the store (all names are unique) |
| is_online | | 1 if the store is online, 0 if physical |

**PriceObservation**

| Column | Key | Description |
|---|---|---|
| obs_id | Primary Key | Unique ID for a price observation |
| product_id | Foreign Key | Product that was priced (references Product) |
| store_id | Foreign Key | Store where the price was seen (references Store) |
| price | | Price that was observed |
| observed_date | | Date the price was seen |
| note | | Optional note (for example "clearance sale") |

**Relationships.** One product can have many price observations, and each observation belongs to one product (one-to-many). One store can also have many price observations, and each observation belongs to one store (one-to-many). Together, Product and Store have a many-to-many relationship, because a product is priced at many stores and a store prices many products. PriceObservation resolves this relationship and also stores the data that belongs to it (price and date).

**Foreign keys.** `product_id` in PriceObservation references `product_id` in Product. `store_id` in PriceObservation references `store_id` in Store. Deleting a product or a store deletes its observations (ON DELETE CASCADE).

Product has no foreign key because it is a standalone table. The same is true for Store. Their only link is through PriceObservation.

---

## 3. SQL and Relational Algebra

The following SQL and relational algebra examples show how the database will support the main features of the application. Throughout, **PO** abbreviates PriceObservation.

**Notation:** σ = selection, π = projection, ⋈ = join, ∪ = union, − = set difference, × = Cartesian product, γ = grouping/aggregation, ρ = rename. Subscripts are written with an underscore, for example π_(columns).

### 3.1 Database Creation

**SQL Code:**

```sql
PRAGMA foreign_keys = ON;

CREATE TABLE Product (
    product_id    INTEGER PRIMARY KEY,
    product_name  VARCHAR(100) NOT NULL,
    category      VARCHAR(50),
    target_price  DECIMAL(8,2) CHECK (target_price > 0)
);

CREATE TABLE Store (
    store_id    INTEGER PRIMARY KEY,
    store_name  VARCHAR(100) NOT NULL UNIQUE,
    is_online   INTEGER NOT NULL DEFAULT 0 CHECK (is_online IN (0, 1))
);

CREATE TABLE PriceObservation (
    obs_id         INTEGER PRIMARY KEY,
    product_id     INTEGER NOT NULL,
    store_id       INTEGER NOT NULL,
    price          DECIMAL(8,2) NOT NULL CHECK (price > 0),
    observed_date  DATE NOT NULL,
    note           VARCHAR(200),
    FOREIGN KEY (product_id) REFERENCES Product(product_id) ON DELETE CASCADE,
    FOREIGN KEY (store_id)   REFERENCES Store(store_id)     ON DELETE CASCADE,
    UNIQUE (product_id, store_id, observed_date)
);
```

The primary keys uniquely identify records in each table. The two foreign keys in PriceObservation create the relationships to Product and Store. I also added a few simple constraints: store names must be unique, prices must be more than zero, and a product can only have one reading per store per day.

**Sample Data:**

```sql
INSERT INTO Product (product_id, product_name, category, target_price) VALUES
(1, 'Noise-Cancelling Headphones', 'Electronics', 250.00),
(2, 'Running Shoes',               'Apparel',      90.00),
(3, 'Espresso Grinder',            'Kitchen',      NULL);

INSERT INTO Store (store_id, store_name, is_online) VALUES
(1, 'Amazon', 1), (2, 'Best Buy', 0), (3, 'Target', 0);

INSERT INTO PriceObservation
    (obs_id, product_id, store_id, price, observed_date) VALUES
(1, 1, 1, 299.99, '2026-09-01'),
(2, 1, 2, 279.99, '2026-09-15'),
(3, 1, 1, 249.99, '2026-10-01'),
(4, 2, 3, 110.00, '2026-09-10'),
(5, 2, 3,  89.99, '2026-10-02'),
(6, 2, 1,  95.00, '2026-10-02');
```

### 3.2 Query 1: Display Product Information

**Relational Algebra:**

```
π_(product_id, product_name, category, target_price) (Product)
```

**SQL:**

```sql
SELECT product_id, product_name, category, target_price
FROM Product;
```

**Expected result:** Noise-Cancelling Headphones, Running Shoes, Espresso Grinder

Projection picks the columns needed for the product list screen. The Espresso Grinder shows no target price because its target is NULL.

### 3.3 Query 2: Filter Products by Category

**Relational Algebra:**

```
π_(product_name, target_price) ( σ_(category = 'Electronics') (Product) )
```

**SQL:**

```sql
SELECT product_name, target_price
FROM Product
WHERE category = 'Electronics';
```

**Expected result:** Noise-Cancelling Headphones with target price 250.00

Selection keeps only products in one category, and projection shows the two columns needed. This supports the category filter on the product list.

### 3.4 Query 3: Price History of One Product with Store Names

**Relational Algebra:**

```
π_(store_name, price, observed_date)
  ( σ_(product_id = 1)(PO)  ⋈_(PO.store_id = Store.store_id)  Store )
```

**SQL:**

```sql
SELECT Store.store_name, PO.price, PO.observed_date
FROM PriceObservation PO
JOIN Store ON PO.store_id = Store.store_id
WHERE PO.product_id = 1
ORDER BY PO.observed_date DESC;
```

**Expected result:** Amazon 249.99 (2026-10-01), Best Buy 279.99 (2026-09-15), Amazon 299.99 (2026-09-01)

This query shows the relationship between PriceObservation and Store. Selection keeps only the observations for product 1, the join matches each observation to its store using `store_id`, and projection shows the store name next to each price. This powers the price history screen.

### 3.5 Query 4: Lowest and Average Price per Product

**Relational Algebra:**

```
Stats = γ_(product_id; MIN(price)→low, AVG(price)→avg_price, COUNT(*)→n) (PO)

π_(product_name, low, avg_price, n) ( Product ⋈ Stats )
```

**SQL:**

```sql
SELECT Product.product_name,
       MIN(PO.price) AS low,
       ROUND(AVG(PO.price), 2) AS avg_price,
       COUNT(*) AS n
FROM Product
JOIN PriceObservation PO ON Product.product_id = PO.product_id
GROUP BY Product.product_id;
```

**Expected result:** Headphones 249.99 / 276.66 / 3, Running Shoes 89.99 / 98.33 / 3

Grouping calculates the lowest price, average price, and number of observations for each product. The join then attaches the product name. These numbers feed the stats card on the product screen and are the basis of the smart buy rule. The Espresso Grinder does not appear because it has no observations yet.

### 3.6 Query 5: Smart Buy-Now Signal (Main Feature)

**Relational Algebra:**

```
Stale = π_(o1.*) ( σ_(o1.product_id = o2.product_id ∧ o1.store_id = o2.store_id
                      ∧ o1.observed_date < o2.observed_date)
                   ( ρ_o1(PO) × ρ_o2(PO) ) )

Latest = PO − Stale

Stats = γ_(product_id; MIN(price)→low, AVG(price)→avg_price, COUNT(*)→n) (PO)

TargetHit = π_(product_name, store_name, price)
              ( σ_(price ≤ target_price) ( Latest ⋈ Product ⋈ Store ) )

DealHit = π_(product_name, store_name, price)
            ( σ_(n ≥ 3 ∧ price ≤ 1.05·low ∧ price < avg_price)
              ( Latest ⋈ Stats ⋈ Product ⋈ Store ) )

BuyNow = TargetHit ∪ DealHit
```

**SQL:**

```sql
WITH stats AS (
    SELECT product_id, MIN(price) AS low,
           AVG(price) AS avg_price, COUNT(*) AS n
    FROM PriceObservation
    GROUP BY product_id
),
latest AS (
    SELECT po.* FROM PriceObservation po
    WHERE NOT EXISTS (
        SELECT 1 FROM PriceObservation newer
        WHERE newer.product_id = po.product_id
          AND newer.store_id = po.store_id
          AND newer.observed_date > po.observed_date)
)
SELECT p.product_name, s.store_name, l.price
FROM latest l
JOIN Product p ON l.product_id = p.product_id
JOIN Store   s ON l.store_id   = s.store_id
WHERE l.price <= p.target_price
UNION
SELECT p.product_name, s.store_name, l.price
FROM latest l
JOIN Product p  ON l.product_id = p.product_id
JOIN Store   s  ON l.store_id   = s.store_id
JOIN stats   st ON l.product_id = st.product_id
WHERE st.n >= 3
  AND l.price <= 1.05 * st.low
  AND l.price <  st.avg_price;
```

**Expected result:** Noise-Cancelling Headphones at Amazon for 249.99, and Running Shoes at Target for 89.99

An observation is stale if a later one exists for the same product and store, so Latest keeps only the newest price per product/store pair (this is why the 299.99 Amazon price is ignored). TargetHit compares each latest price with the product's target price. DealHit uses the statistics from Query 4 to find prices within 5% of the lowest price and below the average. The union combines both rules. Headphones at Best Buy (279.99) is above the average, and Shoes at Amazon (95.00) is above 1.05 × 89.99 = 94.49, so neither triggers. A product with a NULL target price can only trigger through DealHit, because a comparison with NULL is never true.

### 3.7 How the Queries Support the App

| App feature | Query |
|---|---|
| Product list screen | Query 1 |
| Filter products by category | Query 2 |
| Price history screen | Query 3 |
| Lowest / average price stats card | Query 4 |
| Smart buy-now signal and notification | Query 5 |

---

## 4. AI Utilization Plan

I plan to use generative AI mainly as a learning and debugging tool during the project. My main AI tool will be [ChatGPT / Claude / Gemini: edit to match your actual tools]. I may also use a second tool when I want to compare explanations, verify documentation, or get another perspective on a problem.

I do not plan to have AI generate the entire project without understanding it. Instead, I will use it to learn concepts, troubleshoot errors, review my decisions, and understand code that I am working with. I will make the key design decisions myself, including the two-rule buy signal, the 5% threshold, the 3-observation minimum, and the constraints on the tables.

### Example uses and prompts

**Learning relational algebra**

"Explain how a self-join with set difference can find the latest row per group in relational algebra, using a small price-history table. Walk through the idea before giving the notation."

**SQL debugging**

"I am getting this SQL error. Explain what the error means and help me identify what I should check before giving me the corrected query."

**Database design**

"Review my initial price-tracking database design and point out possible duplicates or dependencies that I should investigate. Don't redesign it for me yet."

**Understanding Android/database code**

"Explain this Android Room database code line by line. I want to understand how the application is interacting with the database before I make changes."

I will verify important AI suggestions by running the SQL in SQLite against my sample data, comparing the output to the expected results in this document, and checking documentation when necessary. I will also keep an AI log throughout the project to record meaningful AI interactions and what I learned from them.
