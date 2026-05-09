-- Run in MySQL / PostgreSQL

CREATE DATABASE smart_inventory;
USE smart_inventory;

CREATE TABLE Warehouse (
    warehouse_id INT PRIMARY KEY AUTO_INCREMENT,
    name         VARCHAR(100) NOT NULL,
    location     VARCHAR(200),
    capacity     INT DEFAULT 10000
);

CREATE TABLE Supplier (
    supplier_id INT PRIMARY KEY AUTO_INCREMENT,
    name        VARCHAR(100) NOT NULL,
    contact     VARCHAR(15),
    email       VARCHAR(100) UNIQUE
);

CREATE TABLE Product (
    product_id    INT PRIMARY KEY AUTO_INCREMENT,
    name          VARCHAR(150) NOT NULL,
    category      VARCHAR(50),
    unit_price    DECIMAL(10,2) NOT NULL,
    reorder_level INT DEFAULT 50
);

CREATE TABLE Employee (
    emp_id       INT PRIMARY KEY AUTO_INCREMENT,
    warehouse_id INT,
    name         VARCHAR(100) NOT NULL,
    role         ENUM('Manager','Staff','Security') DEFAULT 'Staff',
    hire_date    DATE,
    FOREIGN KEY (warehouse_id) REFERENCES Warehouse(warehouse_id)
);

CREATE TABLE Stock (
    stock_id     INT PRIMARY KEY AUTO_INCREMENT,
    warehouse_id INT NOT NULL,
    product_id   INT NOT NULL,
    supplier_id  INT,
    quantity     INT DEFAULT 0,
    last_updated DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (warehouse_id) REFERENCES Warehouse(warehouse_id),
    FOREIGN KEY (product_id)   REFERENCES Product(product_id),
    FOREIGN KEY (supplier_id)  REFERENCES Supplier(supplier_id),
    UNIQUE KEY uq_warehouse_product (warehouse_id, product_id)
);

CREATE TABLE `Order` (
    order_id     INT PRIMARY KEY AUTO_INCREMENT,
    warehouse_id INT NOT NULL,
    order_date   DATETIME DEFAULT CURRENT_TIMESTAMP,
    status       ENUM('Pending','Approved','Shipped','Delivered','Cancelled') DEFAULT 'Pending',
    total_amount DECIMAL(12,2) DEFAULT 0.00,
    FOREIGN KEY (warehouse_id) REFERENCES Warehouse(warehouse_id)
);

CREATE TABLE OrderItem (
    item_id    INT PRIMARY KEY AUTO_INCREMENT,
    order_id   INT NOT NULL,
    product_id INT NOT NULL,
    quantity   INT NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (order_id)   REFERENCES `Order`(order_id),
    FOREIGN KEY (product_id) REFERENCES Product(product_id)
);
select * from OrderItem;
CREATE TABLE bad_stock (
    stock_id     INT,
    warehouse_name VARCHAR(100),   -- ← repeated for every row (1NF violation)
    warehouse_loc  VARCHAR(200),   -- ← depends on warehouse, not stock_id (2NF violation)
    product_name   VARCHAR(150),   -- ← transitive dependency (3NF violation)
    supplier_email VARCHAR(100),
    quantity       INT
);
-- ── Seed Data ──────────────────────────────────────────
INSERT INTO Warehouse (name, location, capacity) VALUES
    ('Central Hub',  'Bangalore',  50000),
    ('South Depot',  'Chennai',    30000),
    ('North Station','Delhi',      40000);

INSERT INTO Supplier (name, contact, email) VALUES
    ('TechParts Ltd',  '9876543210', 'tp@techparts.in'),
    ('QuickGoods Co',  '8765432109', 'qg@quickgoods.in'),
    ('Global Supply',  '7654321098', 'gs@globalsup.in');

INSERT INTO Product (name, category, unit_price, reorder_level) VALUES
    ('Laptop 15"',     'Electronics', 55000.00, 20),
    ('USB-C Hub',      'Electronics',  1500.00, 100),
    ('Office Chair',   'Furniture',    8000.00, 30),
    ('A4 Paper Ream',  'Stationery',    350.00, 500),
    ('Wireless Mouse', 'Electronics',  1200.00, 150);

INSERT INTO Employee (warehouse_id, name, role, hire_date) VALUES
    (1, 'Arjun Sharma',  'Manager', '2021-03-15'),
    (1, 'Priya Nair',    'Staff',   '2022-07-01'),
    (2, 'Karan Mehta',   'Manager', '2020-11-20'),
    (3, 'Sunita Reddy',  'Staff',   '2023-01-10');

INSERT INTO Stock (warehouse_id, product_id, supplier_id, quantity) VALUES
    (1, 1, 1, 120),   -- Laptops at Central Hub
    (1, 2, 1, 500),   -- USB Hubs at Central Hub
    (1, 3, 2, 80),    -- Chairs at Central Hub
    (2, 4, 3, 2000),  -- Paper at South Depot
    (2, 5, 2, 350),   -- Mice at South Depot
    (3, 1, 1, 60),    -- Laptops at North Station
    (3, 5, 2, 200);   -- Mice at North Station

-- ── Update ─────────────────────────────────────────────
-- Restock after delivery
UPDATE Stock
SET quantity = quantity + 200
WHERE warehouse_id = 2 AND product_id = 4;

-- Update product price
UPDATE Product
SET unit_price = 58000.00
WHERE product_id=1;
select * from product;


-- ── Delete ─────────────────────────────────────────────
-- Cancel pending orders older than 30 days
DELETE FROM Product
WHERE product_id = 4
  AND NOT EXISTS (
      SELECT 1 FROM Stock WHERE product_id = 4 AND quantity > 0
  );
  
select*from ordertable;
-- ── 1. Current stock across all warehouses ─────────────
SELECT
    w.name          AS warehouse,
    p.name          AS product,
    s.quantity,
    p.reorder_level,
    CASE WHEN s.quantity <= p.reorder_level THEN '⚠ Reorder' ELSE 'OK' END AS status
FROM Stock s
JOIN Warehouse w ON s.warehouse_id = w.warehouse_id
JOIN Product   p ON s.product_id   = p.product_id
ORDER BY w.name, s.quantity ASC;

-- ── 2. Low-stock alert (below reorder level) ───────────
SELECT
    p.name         AS product,
    w.name         AS warehouse,
    s.quantity     AS current_qty,
    p.reorder_level,
    sup.name       AS supplier,
    sup.contact    AS call_supplier
FROM Stock s
JOIN Product   p   ON s.product_id   = p.product_id
JOIN Warehouse w   ON s.warehouse_id = w.warehouse_id
JOIN Supplier  sup ON s.supplier_id  = sup.supplier_id
WHERE s.quantity <= p.reorder_level
ORDER BY s.quantity ASC;

-- ── 3. Total inventory value per warehouse ─────────────
SELECT
    w.name                              AS warehouse,
    SUM(s.quantity * p.unit_price)      AS total_value,
    COUNT(DISTINCT p.product_id)        AS product_types,
    SUM(s.quantity)                     AS total_units
FROM Stock s
JOIN Warehouse w ON s.warehouse_id = w.warehouse_id
JOIN Product   p ON s.product_id   = p.product_id
GROUP BY w.warehouse_id, w.name
ORDER BY total_value DESC;

-- ── 4. Order summary with items (JOIN across 3 tables) ─
SELECT
    o.order_id,
    w.name            AS warehouse,
    o.order_date,
    o.status,
    p.name            AS product,
    oi.quantity,
    oi.unit_price,
    oi.quantity * oi.unit_price AS line_total
FROM ordertable o
JOIN Warehouse w  ON o.warehouse_id = w.warehouse_id
JOIN OrderItem oi ON oi.order_id    = o.order_id
JOIN Product   p  ON oi.product_id  = p.product_id
ORDER BY o.order_id, oi.item_id;

-- ── 5. Top 3 products by total quantity across warehouses
SELECT
    p.name          AS product,
    p.category,
    SUM(s.quantity) AS total_stock
FROM Stock s
JOIN Product p ON s.product_id = p.product_id
GROUP BY p.product_id, p.name, p.category
ORDER BY total_stock DESC
LIMIT 3;

-- ── 6. Warehouse employees and their manager ───────────
SELECT
    w.name  AS warehouse,
    e.name  AS employee,
    e.role,
    e.hire_date
FROM Employee e
JOIN Warehouse w ON e.warehouse_id = w.warehouse_id
ORDER BY w.name, e.role;
-- ── VIEW: Live dashboard summary ───────────────────────
CREATE OR REPLACE VIEW vw_inventory_dashboard AS
SELECT
    w.name                                     AS warehouse,
    w.location,
    COUNT(DISTINCT s.product_id)               AS product_types,
    SUM(s.quantity)                            AS total_units,
    ROUND(SUM(s.quantity * p.unit_price), 2)   AS inventory_value,
    SUM(CASE WHEN s.quantity <= p.reorder_level THEN 1 ELSE 0 END) AS low_stock_items
FROM Warehouse w
LEFT JOIN Stock   s ON s.warehouse_id = w.warehouse_id
LEFT JOIN Product p ON p.product_id   = s.product_id
GROUP BY w.warehouse_id, w.name, w.location;

-- Usage: SELECT * FROM vw_inventory_dashboard;


-- ── TRIGGER: Auto-deduct stock when order item is inserted
DELIMITER $$
CREATE TRIGGER trg_deduct_stock_after_order
AFTER INSERT ON OrderItem
FOR EACH ROW
BEGIN
    DECLARE v_wid INT;
    SELECT warehouse_id INTO v_wid
    FROM `Order` WHERE order_id = NEW.order_id;

    UPDATE Stock
    SET quantity = quantity - NEW.quantity
    WHERE warehouse_id = v_wid AND product_id = NEW.product_id;
END$$
DELIMITER ;


-- ── TRIGGER: Update Order total_amount automatically ───
DELIMITER $$
CREATE TRIGGER trg_update_order_total
AFTER INSERT ON OrderItem
FOR EACH ROW
BEGIN
    UPDATE `Order`
    SET total_amount = (
        SELECT SUM(quantity * unit_price)
        FROM OrderItem
        WHERE order_id = NEW.order_id
    )
    WHERE order_id = NEW.order_id;
END$$
DELIMITER ;


-- ── STORED PROCEDURE: Restock a product ────────────────
DELIMITER $$
CREATE PROCEDURE sp_restock(
    IN p_warehouse_id INT,
    IN p_product_id   INT,
    IN p_quantity     INT
)
BEGIN
    IF EXISTS (
        SELECT 1 FROM Stock
        WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id
    ) THEN
        UPDATE Stock
        SET quantity = quantity + p_quantity
        WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id;
    ELSE
        INSERT INTO Stock (warehouse_id, product_id, quantity)
        VALUES (p_warehouse_id, p_product_id, p_quantity);
    END IF;
    SELECT CONCAT('Restocked product ', p_product_id,
                  ' in warehouse ', p_warehouse_id,
                  ' by ', p_quantity, ' units') AS result;
END$$
DELIMITER ;

-- Usage: CALL sp_restock(1, 1, 50);


-- ── STORED PROCEDURE: Place a full order ───────────────
DELIMITER $$
CREATE PROCEDURE sp_place_order(
    IN  p_warehouse_id INT,
    IN  p_product_id   INT,
    IN  p_quantity     INT,
    OUT p_order_id     INT
)
BEGIN
    DECLARE v_price DECIMAL(10,2);
    SELECT unit_price INTO v_price FROM Product WHERE product_id = p_product_id;

    INSERT INTO `Order` (warehouse_id, status) VALUES (p_warehouse_id, 'Pending');
    SET p_order_id = LAST_INSERT_ID();

    INSERT INTO OrderItem (order_id, product_id, quantity, unit_price)
    VALUES (p_order_id, p_product_id, p_quantity, v_price);
    -- The trigger trg_deduct_stock_after_order fires automatically here ↑
END$$
DELIMITER ;

-- Usage:
-- CALL sp_place_order(1, 2, 10, @oid);
-- SELECT @oid;