// webhook-adapter bridges Alertmanager to GitHub's repository_dispatch API.
//
// Alertmanager's webhook receiver can't set custom auth headers or a custom
// JSON body, so it can't call GitHub's dispatch endpoint directly. This tiny
// service accepts Alertmanager's POST on /alert and, for each firing alert,
// POSTs an authenticated repository_dispatch to GitHub, which triggers the
// self-healing GitHub Action (kubectl rollout restart).
//
// Config via env:
//   GITHUB_TOKEN   - PAT with "repo" scope (or fine-grained: contents:write)
//   GITHUB_REPO    - "owner/repo", e.g. nantius/desafio4-fiap-devops
//   DISPATCH_EVENT - repository_dispatch event_type (default: self-heal)
//   LISTEN_ADDR    - default ":8080"
package main

import (
	"bytes"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"time"
)

// alertmanagerPayload is the subset of Alertmanager's webhook body we read.
type alertmanagerPayload struct {
	Status string `json:"status"`
	Alerts []struct {
		Status string            `json:"status"`
		Labels map[string]string `json:"labels"`
	} `json:"alerts"`
}

type dispatchBody struct {
	EventType     string         `json:"event_type"`
	ClientPayload map[string]any `json:"client_payload"`
}

func main() {
	token := os.Getenv("GITHUB_TOKEN")
	repo := os.Getenv("GITHUB_REPO")
	event := os.Getenv("DISPATCH_EVENT")
	if event == "" {
		event = "self-heal"
	}
	addr := os.Getenv("LISTEN_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	if token == "" || repo == "" {
		log.Fatal("GITHUB_TOKEN and GITHUB_REPO are required")
	}

	client := &http.Client{Timeout: 10 * time.Second}

	http.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	http.HandleFunc("/alert", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
		if err != nil {
			http.Error(w, "read error", http.StatusBadRequest)
			return
		}
		var p alertmanagerPayload
		if err := json.Unmarshal(body, &p); err != nil {
			http.Error(w, "bad json", http.StatusBadRequest)
			return
		}

		// Only act on firing alerts.
		if p.Status != "firing" {
			w.WriteHeader(http.StatusOK)
			return
		}

		for _, a := range p.Alerts {
			if a.Status != "firing" {
				continue
			}
			svc := a.Labels["service"]
			if svc == "" {
				svc = "auth-service"
			}
			if err := dispatch(client, token, repo, event, svc); err != nil {
				log.Printf("dispatch failed for service=%s: %v", svc, err)
				http.Error(w, "dispatch failed", http.StatusBadGateway)
				return
			}
			log.Printf("repository_dispatch sent: event=%s service=%s", event, svc)
		}
		w.WriteHeader(http.StatusAccepted)
	})

	log.Printf("webhook-adapter listening on %s (repo=%s, event=%s)", addr, repo, event)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatal(err)
	}
}

// dispatch sends an authenticated repository_dispatch to GitHub.
func dispatch(client *http.Client, token, repo, event, service string) error {
	payload := dispatchBody{
		EventType: event,
		ClientPayload: map[string]any{
			"service": service,
		},
	}
	b, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	// #nosec G704 -- not SSRF: the URL is the fixed GitHub API host; only the
	// repo (operator-set GITHUB_REPO env, never user input) is interpolated.
	req, err := http.NewRequest(http.MethodPost,
		"https://api.github.com/repos/"+repo+"/dispatches", bytes.NewReader(b))
	if err != nil {
		return err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req) // #nosec G704 -- see above; fixed GitHub API host
	if err != nil {
		return err
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode >= 300 {
		msg, _ := io.ReadAll(resp.Body)
		return &httpError{code: resp.StatusCode, body: string(msg)}
	}
	return nil
}

type httpError struct {
	code int
	body string
}

func (e *httpError) Error() string {
	return "github dispatch returned " + http.StatusText(e.code) + ": " + e.body
}
