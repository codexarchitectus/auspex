-- Auspex Alerting Engine Database Schema
-- PostgreSQL 12+
-- Run this after db-init-new.sql to add alerting capabilities

-- ======================================================================
-- ALERT CHANNELS TABLE
-- Stores notification channel configurations (PagerDuty, Slack, Email)
-- ======================================================================
CREATE TABLE IF NOT EXISTS alert_channels (
    id              SERIAL PRIMARY KEY,
    name            VARCHAR(255) NOT NULL,
    type            VARCHAR(50) NOT NULL,  -- 'pagerduty', 'slack_email', 'email', 'webhook'
    config          JSONB NOT NULL,         -- Channel-specific config (API keys, emails, etc.)
    enabled         BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_channel_type CHECK (type IN ('pagerduty', 'slack_email', 'email', 'webhook'))
);

CREATE INDEX idx_alert_channels_enabled ON alert_channels(enabled) WHERE enabled = true;

-- ======================================================================
-- ALERT RULES TABLE
-- Defines alert rules per target (opt-in model)
-- ======================================================================
CREATE TABLE IF NOT EXISTS alert_rules (
    id              SERIAL PRIMARY KEY,
    target_id       INTEGER NOT NULL REFERENCES targets(id) ON DELETE CASCADE,
    name            VARCHAR(255) NOT NULL,
    rule_type       VARCHAR(50) NOT NULL DEFAULT 'status_change',  -- Currently only 'status_change'
    severity        VARCHAR(20) NOT NULL DEFAULT 'critical',       -- 'info', 'warning', 'critical'
    enabled         BOOLEAN NOT NULL DEFAULT true,
    channels        INTEGER[] NOT NULL DEFAULT '{}',               -- Array of alert_channel IDs to notify
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_rule_type CHECK (rule_type IN ('status_change', 'latency_threshold', 'consecutive_failures')),
    CONSTRAINT chk_severity CHECK (severity IN ('info', 'warning', 'critical'))
);

CREATE INDEX idx_alert_rules_target ON alert_rules(target_id);
CREATE INDEX idx_alert_rules_enabled ON alert_rules(enabled) WHERE enabled = true;

-- ======================================================================
-- ALERT HISTORY TABLE
-- Tracks all fired alerts and their lifecycle
-- ======================================================================
CREATE TABLE IF NOT EXISTS alert_history (
    id                  BIGSERIAL PRIMARY KEY,
    rule_id             INTEGER REFERENCES alert_rules(id) ON DELETE SET NULL,
    target_id           INTEGER NOT NULL REFERENCES targets(id) ON DELETE CASCADE,
    alert_type          VARCHAR(50) NOT NULL,       -- 'device_down', 'device_up', etc.
    severity            VARCHAR(20) NOT NULL,
    message             TEXT NOT NULL,
    fired_at            TIMESTAMP NOT NULL DEFAULT NOW(),
    resolved_at         TIMESTAMP,                  -- When device came back up
    notified            BOOLEAN NOT NULL DEFAULT false,
    notification_count  INTEGER NOT NULL DEFAULT 0,
    last_notification   TIMESTAMP,

    CONSTRAINT chk_alert_severity CHECK (severity IN ('info', 'warning', 'critical'))
);

CREATE INDEX idx_alert_history_target ON alert_history(target_id, fired_at DESC);
CREATE INDEX idx_alert_history_fired ON alert_history(fired_at DESC);
CREATE INDEX idx_alert_history_unresolved ON alert_history(resolved_at) WHERE resolved_at IS NULL;

-- ======================================================================
-- ALERT DELIVERIES TABLE
-- Logs each notification attempt to track delivery success/failures
-- ======================================================================
CREATE TABLE IF NOT EXISTS alert_deliveries (
    id                  BIGSERIAL PRIMARY KEY,
    alert_history_id    BIGINT NOT NULL REFERENCES alert_history(id) ON DELETE CASCADE,
    channel_id          INTEGER NOT NULL REFERENCES alert_channels(id) ON DELETE CASCADE,
    channel_type        VARCHAR(50) NOT NULL,
    recipient           TEXT NOT NULL,              -- Email, webhook URL, PagerDuty routing key, etc.
    delivered_at        TIMESTAMP NOT NULL DEFAULT NOW(),
    status              VARCHAR(20) NOT NULL,       -- 'sent', 'failed', 'bounced'
    error_message       TEXT,

    CONSTRAINT chk_delivery_status CHECK (status IN ('sent', 'failed', 'bounced', 'pending'))
);

CREATE INDEX idx_alert_deliveries_history ON alert_deliveries(alert_history_id);
CREATE INDEX idx_alert_deliveries_channel ON alert_deliveries(channel_id);
CREATE INDEX idx_alert_deliveries_status ON alert_deliveries(status);

-- ======================================================================
-- ALERT SUPPRESSIONS TABLE
-- Scheduled maintenance windows to suppress alerts
-- ======================================================================
CREATE TABLE IF NOT EXISTS alert_suppressions (
    id              SERIAL PRIMARY KEY,
    name            VARCHAR(255) NOT NULL,
    target_id       INTEGER REFERENCES targets(id) ON DELETE CASCADE,  -- NULL = global suppression
    start_time      TIMESTAMP NOT NULL,
    end_time        TIMESTAMP NOT NULL,
    recurrence      VARCHAR(50),                    -- NULL, 'daily', 'weekly', 'monthly'
    days_of_week    INTEGER[],                      -- [0,1,2,3,4,5,6] for Sun-Sat, NULL if not weekly
    enabled         BOOLEAN NOT NULL DEFAULT true,
    reason          TEXT,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_suppression_times CHECK (end_time > start_time),
    CONSTRAINT chk_recurrence CHECK (recurrence IN ('daily', 'weekly', 'monthly') OR recurrence IS NULL)
);

CREATE INDEX idx_alert_suppressions_target ON alert_suppressions(target_id);
CREATE INDEX idx_alert_suppressions_enabled ON alert_suppressions(enabled) WHERE enabled = true;
CREATE INDEX idx_alert_suppressions_times ON alert_suppressions(start_time, end_time);

-- ======================================================================
-- ALERT STATE TRACKING TABLE
-- Keeps track of current alert state for de-duplication
-- ======================================================================
CREATE TABLE IF NOT EXISTS alert_state (
    target_id           INTEGER PRIMARY KEY REFERENCES targets(id) ON DELETE CASCADE,
    last_status         VARCHAR(20),                -- Last known status
    last_checked        TIMESTAMP NOT NULL DEFAULT NOW(),
    alert_active        BOOLEAN NOT NULL DEFAULT false,
    active_alert_id     BIGINT REFERENCES alert_history(id) ON DELETE SET NULL,
    state_change_count  INTEGER NOT NULL DEFAULT 0, -- Track flapping
    last_state_change   TIMESTAMP
);

-- ======================================================================
-- SAMPLE ALERT CHANNEL CONFIGURATIONS
-- ======================================================================

-- Example PagerDuty channel (requires integration key)
INSERT INTO alert_channels (name, type, config, enabled) VALUES
    ('PagerDuty - Critical', 'pagerduty',
     '{"routing_key": "YOUR_PAGERDUTY_INTEGRATION_KEY", "severity": "critical"}',
     false);

-- Example Slack email channel (requires Slack email address)
INSERT INTO alert_channels (name, type, config, enabled) VALUES
    ('Slack - #alerts', 'slack_email',
     '{"email": "your-channel-id@your-workspace.slack.com", "from": "auspex@yourdomain.com"}',
     false);

-- Example standard email channel
INSERT INTO alert_channels (name, type, config, enabled) VALUES
    ('Email - Ops Team', 'email',
     '{"to": "ops@yourdomain.com", "from": "auspex-alerts@yourdomain.com"}',
     false);

-- ======================================================================
-- VERIFICATION QUERIES
-- ======================================================================

-- Show all tables
-- SELECT table_name FROM information_schema.tables
-- WHERE table_schema = 'public' AND table_name LIKE 'alert%';

-- Count records
-- SELECT 'alert_channels' as table_name, COUNT(*) FROM alert_channels
-- UNION ALL SELECT 'alert_rules', COUNT(*) FROM alert_rules
-- UNION ALL SELECT 'alert_history', COUNT(*) FROM alert_history
-- UNION ALL SELECT 'alert_deliveries', COUNT(*) FROM alert_deliveries
-- UNION ALL SELECT 'alert_suppressions', COUNT(*) FROM alert_suppressions;
