# app.py  — Flask REST API for Smart Inventory Tracker
# Install: pip install flask mysql-connector-python

from flask import Flask, jsonify,request, abort
from flask_cors import CORS  # Import this
from flask import render_template
import mysql.connector
import os
app = Flask(__name__)
CORS(app) 
from dotenv import load_dotenv
load_dotenv() # Enable it for the whole app

@app.route('/')
def home():
    return render_template('index.html')
DB_CONFIG = {
    "host": os.getenv("DB_HOST"),
    "port": int(os.getenv("DB_PORT")),
    "user": os.getenv("DB_USER"),
    "password": os.getenv("DB_PASSWORD"),
    "database": os.getenv("DB_NAME")
}

def get_connection():
    """Open a fresh DB connection per request."""
    return mysql.connector.connect(**DB_CONFIG)


# ── GET /api/dashboard ─────────────────────────────────
@app.route("/api/dashboard")
def dashboard():
    conn = get_connection()
    cur  = conn.cursor(dictionary=True)
    cur.execute("SELECT * FROM vw_inventory_dashboard")
    rows = cur.fetchall()
    cur.close(); conn.close()
    return jsonify(rows)


# ── GET /api/stock?warehouse_id=1 ──────────────────────
@app.route("/api/stock")
def stock():
    wid  = request.args.get("warehouse_id", type=int)
    conn = get_connection()
    cur  = conn.cursor(dictionary=True)
    query = """
        SELECT p.name AS product, p.category,
               s.quantity, p.reorder_level, p.unit_price,
               CASE WHEN s.quantity <= p.reorder_level THEN 1 ELSE 0 END AS low_stock
        FROM Stock s
        JOIN Product p ON s.product_id = p.product_id
        WHERE (%s IS NULL OR s.warehouse_id = %s)
        ORDER BY low_stock DESC, s.quantity ASC
    """
    cur.execute(query, (wid, wid))
    rows = cur.fetchall()
    cur.close(); conn.close()
    return jsonify(rows)


# ── GET /api/low-stock ─────────────────────────────────
@app.route("/api/low-stock")
def low_stock():
    conn = get_connection()
    cur  = conn.cursor(dictionary=True)
    cur.execute("""
        SELECT p.name, w.name AS warehouse,
               s.quantity, p.reorder_level, sup.name AS supplier, sup.contact
        FROM Stock s
        JOIN Product p   ON s.product_id   = p.product_id
        JOIN Warehouse w ON s.warehouse_id  = w.warehouse_id
        JOIN Supplier sup ON s.supplier_id  = sup.supplier_id
        WHERE s.quantity <= p.reorder_level
        ORDER BY s.quantity ASC
    """)
    rows = cur.fetchall()
    cur.close(); conn.close()
    return jsonify(rows)


# ── POST /api/restock  body: {warehouse_id, product_id, quantity}
@app.route("/api/restock", methods=["POST"])
def restock():
    data = request.get_json()
    wid  = data.get("warehouse_id")
    pid  = data.get("product_id")
    qty  = data.get("quantity")
    if not all([wid, pid, qty]):
        abort(400, "warehouse_id, product_id, quantity required")

    conn = get_connection()
    cur  = conn.cursor()
    cur.callproc("sp_restock", [wid, pid, qty])
    conn.commit()
    cur.close(); conn.close()
    return jsonify({"message": f"Restocked product {pid} in warehouse {wid} by {qty} units"})


# ── POST /api/order  body: {warehouse_id, product_id, quantity}
@app.route("/api/order", methods=["POST"])
def place_order():
    data = request.get_json()
    wid  = data.get("warehouse_id")
    pid  = data.get("product_id")
    qty  = data.get("quantity")
    if not all([wid, pid, qty]):
        abort(400, "warehouse_id, product_id, quantity required")

    conn = get_connection()
    cur  = conn.cursor()
    args = [wid, pid, qty, 0]   # 4th arg is OUT p_order_id
    result = cur.callproc("sp_place_order", args)
    conn.commit()
    order_id = result[3]        # MySQL returns OUT params in result tuple
    cur.close(); conn.close()
    return jsonify({"order_id": order_id, "status": "Pending"})


# ── GET /api/warehouses ────────────────────────────────
@app.route('/api/warehouses')
def warehouses():
    conn = get_connection()
    cur  = conn.cursor(dictionary=True)
    cur.execute("SELECT warehouse_id, name, location FROM Warehouse")
    rows = cur.fetchall()
    cur.close(); conn.close()
    return jsonify(rows)


if __name__ == "__main__":
    app.run(debug=True,host="0.0.0.0", port=5000)