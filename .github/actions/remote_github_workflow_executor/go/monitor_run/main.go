package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
)

func main() {
	owner := flag.String("owner", "", "Target repository owner")
	repo := flag.String("repo", "", "Target repository name")
	runID := flag.String("run-id", "", "Run ID to monitor")
	flag.Parse()

	if *owner == "" || *repo == "" || *runID == "" {
		fmt.Fprintf(os.Stderr, "Error: owner, repo, and run-id are required\n")
		os.Exit(1)
	}

	token := os.Getenv("GH_TOKEN")
	if token == "" {
		fmt.Fprintf(os.Stderr, "Error: GH_TOKEN environment variable not set\n")
		os.Exit(1)
	}

	fmt.Printf("INFO: Monitor Run\n")
	fmt.Printf("INFO:   Target: %s/%s\n", *owner, *repo)
	fmt.Printf("INFO:   Run ID: %s\n", *runID)
	fmt.Printf("INFO:   Poll interval: 10s, max transient errors: 3\n")

	// Monitor the run
	conclusion, runURL, err := monitorRun(token, *owner, *repo, *runID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error monitoring run: %v\n", err)
		os.Exit(1)
	}

	// Write outputs to GITHUB_OUTPUT
	fmt.Printf("INFO: Writing conclusion=%s to GITHUB_OUTPUT\n", conclusion)
	if err := appendOutput("conclusion", conclusion); err != nil {
		fmt.Fprintf(os.Stderr, "Error writing output: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("INFO: Writing run_url to GITHUB_OUTPUT\n")
	if err := appendOutput("run_url", runURL); err != nil {
		fmt.Fprintf(os.Stderr, "Error writing output: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("[%s] Status: completed | Conclusion: %s\n", time.Now().UTC().Format("15:04:05"), conclusion)
	fmt.Printf("Watch here: %s\n", runURL)
}

func monitorRun(token, owner, repo, runID string) (string, string, error) {
	url := fmt.Sprintf("https://api.github.com/repos/%s/%s/actions/runs/%s",
		owner, repo, runID)

	pollInterval := 10 * time.Second
	transientErrorCount := 0
	maxTransientErrors := 3
	fmt.Printf("INFO: [Polling] GET %s\n", url)

	for {
		req, err := http.NewRequest("GET", url, nil)
		if err != nil {
			return "", "", err
		}

		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", token))
		req.Header.Set("Accept", "application/vnd.github+json")

		client := &http.Client{Timeout: 10 * time.Second}
		resp, err := client.Do(req)
		if err != nil {
			return "", "", err
		}
		defer resp.Body.Close()

		if resp.StatusCode != 200 {
			respBody, _ := io.ReadAll(resp.Body)

			if resp.StatusCode == 401 || resp.StatusCode == 403 {
				return "", "", fmt.Errorf("non-retriable poll error (HTTP %d): %s", resp.StatusCode, string(respBody))
			}

			transientErrorCount++
			if transientErrorCount <= maxTransientErrors {
				fmt.Printf("RETRY: Transient poll error (HTTP %d), retrying in %v\n", resp.StatusCode, pollInterval)
				time.Sleep(pollInterval)
				continue
			}

			return "", "", fmt.Errorf("too many transient poll errors (%d): %s", transientErrorCount, string(respBody))
		}

		transientErrorCount = 0

		var result struct {
			Status     string `json:"status"`
			Conclusion string `json:"conclusion"`
			HTMLURL    string `json:"html_url"`
		}

		if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
			return "", "", err
		}

		if result.Status == "" {
			return "", "", fmt.Errorf("invalid API response - missing status field")
		}

		if result.Status == "completed" {
			fmt.Printf("INFO: Run completed with conclusion: %s\n", result.Conclusion)
			return result.Conclusion, result.HTMLURL, nil
		}

		fmt.Printf("INFO: [%s] Status: %s | Conclusion: %s | Waiting %v...\n", time.Now().UTC().Format("15:04:05"), result.Status, result.Conclusion, pollInterval)
		time.Sleep(pollInterval)
	}
}

func appendOutput(key, value string) error {
	outputFile := os.Getenv("GITHUB_OUTPUT")
	if outputFile == "" {
		return fmt.Errorf("GITHUB_OUTPUT environment variable not set")
	}

	f, err := os.OpenFile(outputFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}
	defer f.Close()

	_, err = f.WriteString(fmt.Sprintf("%s=%s\n", key, value))
	return err
}
