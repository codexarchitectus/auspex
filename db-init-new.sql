-- Auspex SNMP Monitor Database Initialization Script
-- PostgreSQL 12+

-- Drop existing tables if they exist (careful in production!)
DROP TABLE IF EXISTS poll_results CASCADE;
DROP TABLE IF EXISTS targets CASCADE;

-- ======================================================================
-- TARGETS TABLE
-- Stores SNMP target devices to be monitored
-- ======================================================================
CREATE TABLE targets (
    id              SERIAL PRIMARY KEY,
    name            VARCHAR(255) NOT NULL,
    host            VARCHAR(255) NOT NULL,
    port            INTEGER NOT NULL DEFAULT 161,
    community       VARCHAR(100) NOT NULL DEFAULT 'public',
    snmp_version    VARCHAR(20) NOT NULL DEFAULT '2c',
    enabled         BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT chk_port CHECK (port > 0 AND port <= 65535),
    CONSTRAINT chk_snmp_version CHECK (snmp_version IN ('1', '2c', '3'))
);

-- Index for querying enabled targets (used by poller)
CREATE INDEX idx_targets_enabled ON targets(enabled) WHERE enabled = true;

-- Index for host lookups
CREATE INDEX idx_targets_host ON targets(host);

-- ======================================================================
-- POLL_RESULTS TABLE
-- Stores historical polling results for all targets
-- ======================================================================
CREATE TABLE poll_results (
    id              BIGSERIAL PRIMARY KEY,
    target_id       INTEGER NOT NULL REFERENCES targets(id) ON DELETE CASCADE,
    status          VARCHAR(20) NOT NULL,
    latency_ms      INTEGER NOT NULL DEFAULT 0,
    message         TEXT,
    polled_at       TIMESTAMP NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT chk_status CHECK (status IN ('up', 'down', 'unknown')),
    CONSTRAINT chk_latency CHECK (latency_ms >= 0)
);

-- Critical index for fetching latest poll per target (used heavily by API)
CREATE INDEX idx_poll_results_target_polled ON poll_results(target_id, polled_at DESC);

-- Index for time-based queries (stats, latency graphs)
CREATE INDEX idx_poll_results_polled_at ON poll_results(polled_at DESC);

-- Index for status filtering
CREATE INDEX idx_poll_results_status ON poll_results(status);

-- ======================================================================
-- SAMPLE DATA (optional - comment out if not needed)
-- ======================================================================

-- Example targets for testing
INSERT INTO targets (name, host, port, community, snmp_version, enabled) VALUES
    ('Router-Core-01', '192.168.1.1', 161, 'public', '2c', true),
    ('Switch-Access-02', '192.168.1.10', 161, 'public', '2c', true),
    ('Firewall-Edge', '192.168.1.254', 161, 'public', '2c', true),
    ('Demo-Disabled', '192.168.1.99', 161, 'public', '2c', false);

-- Example poll results (for demonstration)
INSERT INTO poll_results (target_id, status, latency_ms, message, polled_at) VALUES
    (1, 'up', 45, 'sysName="core-router" sysDescr="Cisco IOS" sysUpTime="12345678"', NOW() - INTERVAL '2 minutes'),
    (1, 'up', 42, 'sysName="core-router" sysDescr="Cisco IOS" sysUpTime="12345678"', NOW() - INTERVAL '1 minute'),
    (2, 'up', 23, 'sysName="access-switch" sysDescr="Cisco Switch" sysUpTime="98765432"', NOW() - INTERVAL '2 minutes'),
    (2, 'down', 0, 'SNMP timeout', NOW() - INTERVAL '1 minute'),
    (3, 'up', 67, 'sysName="edge-fw" sysDescr="Fortinet" sysUpTime="55555555"', NOW() - INTERVAL '2 minutes');

-- ======================================================================
-- VERIFICATION QUERIES
-- ======================================================================

-- Show all tables
-- SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';

-- Show all indexes
-- SELECT tablename, indexname FROM pg_indexes WHERE schemaname = 'public';

-- Count targets and results
-- SELECT 'targets' as table_name, COUNT(*) FROM targets
-- UNION ALL
-- SELECT 'poll_results', COUNT(*) FROM poll_results;
