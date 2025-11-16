// Load environment config
require("dotenv").config({ path: "/opt/auspex/config/auspex.conf" });

const express = require("express");
const path = require("path");
const bodyParser = require("body-parser");
const { Pool } = require("pg");

const app = express();
app.use(bodyParser.json());

// Database connection pool
const pool = new Pool({
    host: process.env.AUSPEX_DB_HOST,
    port: process.env.AUSPEX_DB_PORT,
    user: process.env.AUSPEX_DB_USER,
    password: process.env.AUSPEX_DB_PASSWORD,
    database: process.env.AUSPEX_DB_NAME
});

// Serve static files
app.use(express.static(path.join(__dirname)));


// ======================================================================
// EXISTING ROUTES
// ======================================================================

// GET /api/targets — list targets + latest status
app.get("/api/targets", async (req, res) => {
    try {
        const sql = `
            SELECT t.*,
                   pr.status,
                   pr.latency_ms,
                   pr.message,
                   pr.polled_at
            FROM targets t
            LEFT JOIN LATERAL (
               SELECT * FROM poll_results
               WHERE target_id = t.id
               ORDER BY polled_at DESC
               LIMIT 1
            ) pr ON TRUE
            ORDER BY t.id;
        `;
        const result = await pool.query(sql);
        res.json(result.rows);
    } catch (err) {
        console.error("Error fetching targets:", err);
        res.status(500).json({ error: err.message });
    }
});

// POST /api/targets — add a target
app.post("/api/targets", async (req, res) => {
    try {
        const { name, host, port, community, snmp_version, enabled } = req.body;

        const result = await pool.query(
            `INSERT INTO targets (name, host, port, community, snmp_version, enabled)
             VALUES ($1, $2, $3, $4, $5, $6)
             RETURNING *`,
            [name, host, port, community, snmp_version, enabled]
        );

        res.json(result.rows[0]);
    } catch (err) {
        console.error("Error adding target:", err);
        res.status(500).json({ error: err.message });
    }
});

// PUT /api/targets/:id — update a target
app.put("/api/targets/:id", async (req, res) => {
    try {
        const id = req.params.id;
        const { name, host, port, community, snmp_version, enabled } = req.body;

        const result = await pool.query(
            `UPDATE targets
             SET name=$1, host=$2, port=$3, community=$4, snmp_version=$5, enabled=$6,
                 updated_at=NOW()
             WHERE id=$7
             RETURNING *`,
            [name, host, port, community, snmp_version, enabled, id]
        );

        res.json(result.rows[0]);
    } catch (err) {
        console.error("Error updating target:", err);
        res.status(500).json({ error: err.message });
    }
});

// DELETE /api/targets/:id — soft disable
app.delete("/api/targets/:id", async (req, res) => {
    try {
        const id = req.params.id;

        const result = await pool.query(
            `UPDATE targets SET enabled=false WHERE id=$1 RETURNING *`,
            [id]
        );

        res.json(result.rows[0]);
    } catch (err) {
        console.error("Error disabling target:", err);
        res.status(500).json({ error: err.message });
    }
});


// ======================================================================
// NEW ROUTES FOR TARGET DETAIL PAGE
// ======================================================================

// Get most recent poll result
app.get("/api/targets/:id/latest", async (req, res) => {
    try {
        const id = req.params.id;
        const result = await pool.query(
            `SELECT *
             FROM poll_results
             WHERE target_id = $1
             ORDER BY polled_at DESC
             LIMIT 1`,
            [id]
        );
        res.json(result.rows[0] || {});
    } catch (err) {
        console.error("Error fetching latest poll:", err);
        res.status(500).json({ error: err.message });
    }
});

// Get latency samples for last hour
app.get("/api/targets/:id/latency", async (req, res) => {
    try {
        const id = req.params.id;
        const result = await pool.query(
            `SELECT latency_ms, polled_at
             FROM poll_results
             WHERE target_id = $1
               AND polled_at > NOW() - INTERVAL '1 hour'
             ORDER BY polled_at ASC`,
            [id]
        );
        res.json(result.rows);
    } catch (err) {
        console.error("Error fetching latency data:", err);
        res.status(500).json({ error: err.message });
    }
});

// Get last hour stats: min, max, avg, uptime
app.get("/api/targets/:id/stats", async (req, res) => {
    try {
        const id = req.params.id;
        const result = await pool.query(
            `SELECT 
                MIN(latency_ms) AS min_latency,
                MAX(latency_ms) AS max_latency,
                AVG(latency_ms) AS avg_latency,
                COUNT(*) FILTER (WHERE status='up') AS up_count,
                COUNT(*) AS total_count
             FROM poll_results
             WHERE target_id = $1
               AND polled_at > NOW() - INTERVAL '1 hour'`,
            [id]
        );
        res.json(result.rows[0]);
    } catch (err) {
        console.error("Error fetching stats:", err);
        res.status(500).json({ error: err.message });
    }
});

// Get full target configuration
app.get("/api/targets/:id/info", async (req, res) => {
    try {
        const id = req.params.id;
        const result = await pool.query(
            `SELECT * FROM targets WHERE id=$1`,
            [id]
        );
        res.json(result.rows[0] || {});
    } catch (err) {
        console.error("Error fetching target info:", err);
        res.status(500).json({ error: err.message });
    }
});

// Save/edit target configuration
app.post("/api/targets/:id/update", async (req, res) => {
    try {
        const id = req.params.id;
        const { name, host, port, community, snmp_version, enabled } = req.body;

        const result = await pool.query(
            `UPDATE targets
             SET name=$1, host=$2, port=$3, community=$4,
                 snmp_version=$5, enabled=$6, updated_at=NOW()
             WHERE id=$7
             RETURNING *`,
            [name, host, port, community, snmp_version, enabled, id]
        );

        res.json(result.rows[0]);
    } catch (err) {
        console.error("Error editing target:", err);
        res.status(500).json({ error: err.message });
    }
});

// Hard-delete a target
app.delete("/api/targets/:id/delete", async (req, res) => {
    try {
        const id = req.params.id;

        await pool.query(`DELETE FROM poll_results WHERE target_id=$1`, [id]);
        const result = await pool.query(`DELETE FROM targets WHERE id=$1 RETURNING *`, [id]);

        res.json(result.rows[0]);
    } catch (err) {
        console.error("Error deleting target:", err);
        res.status(500).json({ error: err.message });
    }
});


// ======================================================================
// User guide
// ======================================================================
app.get("/api/user-guide", (req, res) => {
    res.sendFile(path.join(__dirname, "user-guide.html"));
});


// ======================================================================
// Server start
// ======================================================================
const port = process.env.AUSPEX_API_PORT || 8080;
app.listen(port, () => {
    console.log(`Auspex API running on port ${port}`);
});
