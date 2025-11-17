package main

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/smtp"
	"os"
	"strconv"
	"strings"
	"time"

	_ "github.com/lib/pq"
)

// AlertChannel represents a notification channel configuration
type AlertChannel struct {
	ID      int
	Name    string
	Type    string
	Config  map[string]interface{}
	Enabled bool
}

// AlertRule represents an alert rule for a target
type AlertRule struct {
	ID       int
	TargetID int
	Name     string
	RuleType string
	Severity string
	Enabled  bool
	Channels []int
}

// AlertState tracks the current state of a target for de-duplication
type AlertState struct {
	TargetID          int
	LastStatus        string
	LastChecked       time.Time
	AlertActive       bool
	ActiveAlertID     *int64
	StateChangeCount  int
	LastStateChange   *time.Time
}

// AlertSuppression represents a maintenance window
type AlertSuppression struct {
	ID          int
	Name        string
	TargetID    *int
	StartTime   time.Time
	EndTime     time.Time
	Recurrence  *string
	DaysOfWeek  []int
	Enabled     bool
	Reason      string
}

// PollResult represents the latest poll result for a target
type PollResult struct {
	TargetID   int
	TargetName string
	Host       string
	Status     string
	LatencyMs  int
	Message    string
	PolledAt   time.Time
}

// Configuration
var (
	db                     *sql.DB
	checkIntervalSeconds   int
	dedupWindowMinutes     int
	smtpHost               string
	smtpPort               int
	smtpUser               string
	smtpPassword           string
	smtpFrom               string
	pagerdutyDefaultKey    string
)

func main() {
	log.Println("Auspex Alerting Engine starting...")

	// Load configuration
	loadConfig()

	// Connect to database
	dbHost := getenv("AUSPEX_DB_HOST", "localhost")
	dbPort := getenv("AUSPEX_DB_PORT", "5432")
	dbName := getenv("AUSPEX_DB_NAME", "auspexdb")
	dbUser := getenv("AUSPEX_DB_USER", "auspex")
	dbPass := getenv("AUSPEX_DB_PASSWORD", "")

	connStr := fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		dbHost, dbPort, dbUser, dbPass, dbName,
	)

	var err error
	db, err = sql.Open("postgres", connStr)
	if err != nil {
		log.Fatalf("failed to open DB: %v", err)
	}
	defer db.Close()

	if err := db.Ping(); err != nil {
		log.Fatalf("failed to ping DB: %v", err)
	}

	log.Printf("Alerter started (check_interval=%ds, dedup_window=%dmin)", checkIntervalSeconds, dedupWindowMinutes)

	// Run initial check
	checkForAlerts()

	// Start periodic checking
	ticker := time.NewTicker(time.Duration(checkIntervalSeconds) * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		checkForAlerts()
	}
}

func loadConfig() {
	var err error

	checkIntervalStr := getenv("AUSPEX_ALERTER_CHECK_INTERVAL_SECONDS", "30")
	checkIntervalSeconds, err = strconv.Atoi(checkIntervalStr)
	if err != nil || checkIntervalSeconds <= 0 {
		checkIntervalSeconds = 30
	}

	dedupWindowStr := getenv("AUSPEX_ALERTER_DEDUP_WINDOW_MINUTES", "15")
	dedupWindowMinutes, err = strconv.Atoi(dedupWindowStr)
	if err != nil || dedupWindowMinutes <= 0 {
		dedupWindowMinutes = 15
	}

	smtpHost = getenv("AUSPEX_SMTP_HOST", "smtp.gmail.com")
	smtpPortStr := getenv("AUSPEX_SMTP_PORT", "587")
	smtpPort, err = strconv.Atoi(smtpPortStr)
	if err != nil {
		smtpPort = 587
	}
	smtpUser = getenv("AUSPEX_SMTP_USER", "")
	smtpPassword = getenv("AUSPEX_SMTP_PASSWORD", "")
	smtpFrom = getenv("AUSPEX_SMTP_FROM", "auspex-alerts@localhost")

	pagerdutyDefaultKey = getenv("AUSPEX_PAGERDUTY_INTEGRATION_KEY", "")
}

// checkForAlerts is the main loop that checks all targets for alert conditions
func checkForAlerts() {
	log.Println("Checking for alert conditions...")

	// Get all enabled alert rules
	rules, err := loadAlertRules()
	if err != nil {
		log.Printf("ERROR: failed to load alert rules: %v", err)
		return
	}

	if len(rules) == 0 {
		log.Println("No enabled alert rules configured")
		return
	}

	log.Printf("Found %d enabled alert rule(s)", len(rules))

	// For each rule, check if conditions are met
	for _, rule := range rules {
		processAlertRule(rule)
	}
}

func processAlertRule(rule AlertRule) {
	// Get latest poll result for this target
	pollResult, err := getLatestPollResult(rule.TargetID)
	if err != nil {
		log.Printf("ERROR: failed to get latest poll for target %d: %v", rule.TargetID, err)
		return
	}

	if pollResult == nil {
		log.Printf("No poll results yet for target %d", rule.TargetID)
		return
	}

	// Get current alert state for this target
	state, err := getAlertState(rule.TargetID)
	if err != nil {
		log.Printf("ERROR: failed to get alert state for target %d: %v", rule.TargetID, err)
		return
	}

	// Initialize state if first time
	if state == nil {
		state = &AlertState{
			TargetID:    rule.TargetID,
			LastStatus:  pollResult.Status,
			LastChecked: time.Now(),
			AlertActive: false,
		}
		if err := saveAlertState(state); err != nil {
			log.Printf("ERROR: failed to save initial alert state: %v", err)
			return
		}
		log.Printf("Initialized alert state for target %d (%s) status=%s", rule.TargetID, pollResult.TargetName, pollResult.Status)
		return
	}

	// Check for status change (up -> down or down -> up)
	if state.LastStatus != pollResult.Status {
		log.Printf("Status change detected for target %d (%s): %s -> %s",
			rule.TargetID, pollResult.TargetName, state.LastStatus, pollResult.Status)

		// Handle status change based on rule type
		if rule.RuleType == "status_change" {
			handleStatusChange(rule, pollResult, state)
		}

		// Update state
		now := time.Now()
		state.LastStatus = pollResult.Status
		state.LastChecked = now
		state.StateChangeCount++
		state.LastStateChange = &now

		if err := saveAlertState(state); err != nil {
			log.Printf("ERROR: failed to update alert state: %v", err)
		}
	} else {
		// No change, just update last checked time
		state.LastChecked = time.Now()
		if err := saveAlertState(state); err != nil {
			log.Printf("ERROR: failed to update alert state: %v", err)
		}
	}
}

func handleStatusChange(rule AlertRule, pollResult *PollResult, state *AlertState) {
	// Check if target is currently suppressed
	if isSuppressed(rule.TargetID) {
		log.Printf("Target %d (%s) is suppressed, skipping alert", rule.TargetID, pollResult.TargetName)
		return
	}

	var alertType string
	var message string

	if pollResult.Status == "down" {
		// Device went down
		alertType = "device_down"
		message = fmt.Sprintf("Target %s (%s) is DOWN - %s",
			pollResult.TargetName, pollResult.Host, pollResult.Message)

		// Create alert if not already active
		if !state.AlertActive {
			alertID, err := createAlert(rule, pollResult, alertType, message)
			if err != nil {
				log.Printf("ERROR: failed to create alert: %v", err)
				return
			}

			state.AlertActive = true
			state.ActiveAlertID = &alertID

			// Send notifications
			sendNotifications(rule, pollResult, alertType, message, alertID)
		}
	} else if pollResult.Status == "up" && state.AlertActive {
		// Device came back up - resolve the alert
		alertType = "device_up"
		message = fmt.Sprintf("Target %s (%s) is back UP (latency: %dms)",
			pollResult.TargetName, pollResult.Host, pollResult.LatencyMs)

		if state.ActiveAlertID != nil {
			if err := resolveAlert(*state.ActiveAlertID); err != nil {
				log.Printf("ERROR: failed to resolve alert: %v", err)
			}
		}

		// Create recovery notification
		alertID, err := createAlert(rule, pollResult, alertType, message)
		if err != nil {
			log.Printf("ERROR: failed to create recovery alert: %v", err)
			return
		}

		// Automatically resolve recovery alert
		if err := resolveAlert(alertID); err != nil {
			log.Printf("ERROR: failed to resolve recovery alert: %v", err)
		}

		state.AlertActive = false
		state.ActiveAlertID = nil

		// Send recovery notifications
		sendNotifications(rule, pollResult, alertType, message, alertID)
	}
}

func isSuppressed(targetID int) bool {
	now := time.Now()

	var count int
	err := db.QueryRow(`
		SELECT COUNT(*)
		FROM alert_suppressions
		WHERE enabled = true
		  AND (target_id = $1 OR target_id IS NULL)
		  AND (
		      -- One-time suppression
		      (recurrence IS NULL AND start_time <= $2 AND end_time >= $2)
		      OR
		      -- Daily recurrence
		      (recurrence = 'daily' AND EXTRACT(HOUR FROM start_time) <= EXTRACT(HOUR FROM $2::time)
		       AND EXTRACT(HOUR FROM end_time) >= EXTRACT(HOUR FROM $2::time))
		      OR
		      -- Weekly recurrence
		      (recurrence = 'weekly' AND $3 = ANY(days_of_week)
		       AND EXTRACT(HOUR FROM start_time) <= EXTRACT(HOUR FROM $2::time)
		       AND EXTRACT(HOUR FROM end_time) >= EXTRACT(HOUR FROM $2::time))
		  )
	`, targetID, now, int(now.Weekday())).Scan(&count)

	if err != nil {
		log.Printf("ERROR: failed to check suppressions: %v", err)
		return false
	}

	return count > 0
}

func createAlert(rule AlertRule, pollResult *PollResult, alertType, message string) (int64, error) {
	var alertID int64
	err := db.QueryRow(`
		INSERT INTO alert_history (rule_id, target_id, alert_type, severity, message, fired_at, notified)
		VALUES ($1, $2, $3, $4, $5, NOW(), true)
		RETURNING id
	`, rule.ID, rule.TargetID, alertType, rule.Severity, message).Scan(&alertID)

	if err != nil {
		return 0, err
	}

	log.Printf("Created alert #%d for target %d (%s) type=%s severity=%s",
		alertID, rule.TargetID, pollResult.TargetName, alertType, rule.Severity)

	return alertID, nil
}

func resolveAlert(alertID int64) error {
	_, err := db.Exec(`
		UPDATE alert_history
		SET resolved_at = NOW()
		WHERE id = $1
	`, alertID)

	if err == nil {
		log.Printf("Resolved alert #%d", alertID)
	}

	return err
}

func sendNotifications(rule AlertRule, pollResult *PollResult, alertType, message string, alertID int64) {
	if len(rule.Channels) == 0 {
		log.Printf("No channels configured for rule %d, skipping notifications", rule.ID)
		return
	}

	// Load alert channels
	channels, err := loadAlertChannels(rule.Channels)
	if err != nil {
		log.Printf("ERROR: failed to load alert channels: %v", err)
		return
	}

	for _, channel := range channels {
		if !channel.Enabled {
			log.Printf("Channel %d (%s) is disabled, skipping", channel.ID, channel.Name)
			continue
		}

		log.Printf("Sending alert to channel %d (%s) type=%s", channel.ID, channel.Name, channel.Type)

		var status, errMsg string

		switch channel.Type {
		case "pagerduty":
			err = sendPagerDutyAlert(channel, pollResult, alertType, message, rule.Severity)
		case "slack_email":
			err = sendSlackEmailAlert(channel, pollResult, alertType, message, rule.Severity)
		case "email":
			err = sendEmailAlert(channel, pollResult, alertType, message, rule.Severity)
		default:
			err = fmt.Errorf("unsupported channel type: %s", channel.Type)
		}

		if err != nil {
			status = "failed"
			errMsg = err.Error()
			log.Printf("ERROR: Failed to send to channel %d (%s): %v", channel.ID, channel.Name, err)
		} else {
			status = "sent"
			log.Printf("Successfully sent alert to channel %d (%s)", channel.ID, channel.Name)
		}

		// Log delivery attempt
		logDelivery(alertID, channel, pollResult, status, errMsg)
	}

	// Update notification count
	_, err = db.Exec(`
		UPDATE alert_history
		SET notification_count = notification_count + 1,
		    last_notification = NOW()
		WHERE id = $1
	`, alertID)

	if err != nil {
		log.Printf("ERROR: failed to update notification count: %v", err)
	}
}

func sendPagerDutyAlert(channel AlertChannel, pollResult *PollResult, alertType, message, severity string) error {
	// Get routing key from config
	routingKey, ok := channel.Config["routing_key"].(string)
	if !ok || routingKey == "" {
		return fmt.Errorf("missing routing_key in channel config")
	}

	// Map severity to PagerDuty severity
	pdSeverity := "error"
	switch severity {
	case "info":
		pdSeverity = "info"
	case "warning":
		pdSeverity = "warning"
	case "critical":
		pdSeverity = "critical"
	}

	// Determine event_action (trigger for down, resolve for up)
	eventAction := "trigger"
	if alertType == "device_up" {
		eventAction = "resolve"
	}

	// Build PagerDuty Events API v2 payload
	payload := map[string]interface{}{
		"routing_key":  routingKey,
		"event_action": eventAction,
		"dedup_key":    fmt.Sprintf("auspex-target-%d", pollResult.TargetID),
		"payload": map[string]interface{}{
			"summary":   message,
			"severity":  pdSeverity,
			"source":    "auspex-monitor",
			"timestamp": time.Now().Format(time.RFC3339),
			"custom_details": map[string]interface{}{
				"target_id":   pollResult.TargetID,
				"target_name": pollResult.TargetName,
				"host":        pollResult.Host,
				"status":      pollResult.Status,
				"latency_ms":  pollResult.LatencyMs,
				"message":     pollResult.Message,
			},
		},
	}

	jsonData, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("failed to marshal PagerDuty payload: %v", err)
	}

	// Send to PagerDuty Events API v2
	resp, err := http.Post(
		"https://events.pagerduty.com/v2/enqueue",
		"application/json",
		bytes.NewBuffer(jsonData),
	)
	if err != nil {
		return fmt.Errorf("failed to send to PagerDuty: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 202 {
		return fmt.Errorf("PagerDuty returned status %d", resp.StatusCode)
	}

	return nil
}

func sendSlackEmailAlert(channel AlertChannel, pollResult *PollResult, alertType, message, severity string) error {
	// Get Slack email from config
	slackEmail, ok := channel.Config["email"].(string)
	if !ok || slackEmail == "" {
		return fmt.Errorf("missing email in channel config")
	}

	fromEmail, ok := channel.Config["from"].(string)
	if !ok || fromEmail == "" {
		fromEmail = smtpFrom
	}

	// Build email
	subject := fmt.Sprintf("[%s] Auspex Alert: %s", strings.ToUpper(severity), pollResult.TargetName)

	emoji := "🔴"
	if alertType == "device_up" {
		emoji = "✅"
	}

	body := fmt.Sprintf(`%s %s

Target: %s
Host: %s
Status: %s
Time: %s

%s

---
Auspex SNMP Monitor
`, emoji, message, pollResult.TargetName, pollResult.Host,
		strings.ToUpper(pollResult.Status),
		time.Now().Format("2006-01-02 15:04:05 MST"),
		pollResult.Message)

	return sendEmail(fromEmail, slackEmail, subject, body)
}

func sendEmailAlert(channel AlertChannel, pollResult *PollResult, alertType, message, severity string) error {
	// Get email from config
	toEmail, ok := channel.Config["to"].(string)
	if !ok || toEmail == "" {
		return fmt.Errorf("missing to address in channel config")
	}

	fromEmail, ok := channel.Config["from"].(string)
	if !ok || fromEmail == "" {
		fromEmail = smtpFrom
	}

	// Build email
	subject := fmt.Sprintf("[%s] Auspex Alert: %s", strings.ToUpper(severity), pollResult.TargetName)

	emoji := "🔴"
	if alertType == "device_up" {
		emoji = "✅"
	}

	body := fmt.Sprintf(`%s %s

Target: %s
Host: %s
Status: %s
Latency: %dms
Time: %s

Details:
%s

---
Auspex SNMP Monitor
View Target: http://localhost:8080/target.html?id=%d
`, emoji, message, pollResult.TargetName, pollResult.Host,
		strings.ToUpper(pollResult.Status), pollResult.LatencyMs,
		time.Now().Format("2006-01-02 15:04:05 MST"),
		pollResult.Message, pollResult.TargetID)

	return sendEmail(fromEmail, toEmail, subject, body)
}

func sendEmail(from, to, subject, body string) error {
	if smtpHost == "" || smtpUser == "" || smtpPassword == "" {
		return fmt.Errorf("SMTP not configured (check AUSPEX_SMTP_* environment variables)")
	}

	// Build email message
	msg := fmt.Sprintf("From: %s\r\nTo: %s\r\nSubject: %s\r\n\r\n%s", from, to, subject, body)

	// SMTP authentication
	auth := smtp.PlainAuth("", smtpUser, smtpPassword, smtpHost)

	// Send email
	addr := fmt.Sprintf("%s:%d", smtpHost, smtpPort)
	err := smtp.SendMail(addr, auth, from, []string{to}, []byte(msg))
	if err != nil {
		return fmt.Errorf("failed to send email: %v", err)
	}

	return nil
}

func logDelivery(alertID int64, channel AlertChannel, pollResult *PollResult, status, errMsg string) {
	recipient := "unknown"
	if channel.Type == "pagerduty" {
		if key, ok := channel.Config["routing_key"].(string); ok {
			recipient = "PagerDuty:" + key[:8] + "..."
		}
	} else if channel.Type == "slack_email" {
		if email, ok := channel.Config["email"].(string); ok {
			recipient = email
		}
	} else if channel.Type == "email" {
		if email, ok := channel.Config["to"].(string); ok {
			recipient = email
		}
	}

	_, err := db.Exec(`
		INSERT INTO alert_deliveries (alert_history_id, channel_id, channel_type, recipient, status, error_message)
		VALUES ($1, $2, $3, $4, $5, $6)
	`, alertID, channel.ID, channel.Type, recipient, status, errMsg)

	if err != nil {
		log.Printf("ERROR: failed to log delivery: %v", err)
	}
}

func loadAlertRules() ([]AlertRule, error) {
	rows, err := db.Query(`
		SELECT id, target_id, name, rule_type, severity, enabled, channels
		FROM alert_rules
		WHERE enabled = true
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var rules []AlertRule
	for rows.Next() {
		var rule AlertRule
		var channelsArray string

		err := rows.Scan(&rule.ID, &rule.TargetID, &rule.Name, &rule.RuleType,
			&rule.Severity, &rule.Enabled, &channelsArray)
		if err != nil {
			return nil, err
		}

		// Parse channels array (PostgreSQL array format: {1,2,3})
		if channelsArray != "{}" {
			channelsArray = strings.Trim(channelsArray, "{}")
			if channelsArray != "" {
				channelStrs := strings.Split(channelsArray, ",")
				for _, cs := range channelStrs {
					if id, err := strconv.Atoi(cs); err == nil {
						rule.Channels = append(rule.Channels, id)
					}
				}
			}
		}

		rules = append(rules, rule)
	}

	return rules, rows.Err()
}

func loadAlertChannels(channelIDs []int) ([]AlertChannel, error) {
	if len(channelIDs) == 0 {
		return []AlertChannel{}, nil
	}

	// Build IN clause
	placeholders := make([]string, len(channelIDs))
	args := make([]interface{}, len(channelIDs))
	for i, id := range channelIDs {
		placeholders[i] = fmt.Sprintf("$%d", i+1)
		args[i] = id
	}

	query := fmt.Sprintf(`
		SELECT id, name, type, config, enabled
		FROM alert_channels
		WHERE id IN (%s)
	`, strings.Join(placeholders, ","))

	rows, err := db.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var channels []AlertChannel
	for rows.Next() {
		var channel AlertChannel
		var configJSON []byte

		err := rows.Scan(&channel.ID, &channel.Name, &channel.Type, &configJSON, &channel.Enabled)
		if err != nil {
			return nil, err
		}

		// Parse JSON config
		if err := json.Unmarshal(configJSON, &channel.Config); err != nil {
			log.Printf("WARNING: failed to parse config for channel %d: %v", channel.ID, err)
			channel.Config = make(map[string]interface{})
		}

		channels = append(channels, channel)
	}

	return channels, rows.Err()
}

func getLatestPollResult(targetID int) (*PollResult, error) {
	var result PollResult
	err := db.QueryRow(`
		SELECT pr.target_id, t.name, t.host, pr.status, pr.latency_ms, pr.message, pr.polled_at
		FROM poll_results pr
		JOIN targets t ON t.id = pr.target_id
		WHERE pr.target_id = $1
		ORDER BY pr.polled_at DESC
		LIMIT 1
	`, targetID).Scan(&result.TargetID, &result.TargetName, &result.Host,
		&result.Status, &result.LatencyMs, &result.Message, &result.PolledAt)

	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	return &result, nil
}

func getAlertState(targetID int) (*AlertState, error) {
	var state AlertState
	err := db.QueryRow(`
		SELECT target_id, last_status, last_checked, alert_active,
		       active_alert_id, state_change_count, last_state_change
		FROM alert_state
		WHERE target_id = $1
	`, targetID).Scan(&state.TargetID, &state.LastStatus, &state.LastChecked,
		&state.AlertActive, &state.ActiveAlertID, &state.StateChangeCount,
		&state.LastStateChange)

	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	return &state, nil
}

func saveAlertState(state *AlertState) error {
	_, err := db.Exec(`
		INSERT INTO alert_state (target_id, last_status, last_checked, alert_active,
		                         active_alert_id, state_change_count, last_state_change)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		ON CONFLICT (target_id) DO UPDATE
		SET last_status = EXCLUDED.last_status,
		    last_checked = EXCLUDED.last_checked,
		    alert_active = EXCLUDED.alert_active,
		    active_alert_id = EXCLUDED.active_alert_id,
		    state_change_count = EXCLUDED.state_change_count,
		    last_state_change = EXCLUDED.last_state_change
	`, state.TargetID, state.LastStatus, state.LastChecked, state.AlertActive,
		state.ActiveAlertID, state.StateChangeCount, state.LastStateChange)

	return err
}

func getenv(key, fallback string) string {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	return v
}
