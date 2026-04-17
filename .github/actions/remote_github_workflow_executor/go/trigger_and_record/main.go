package main

import (
	"bytes"
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
	workflow := flag.String("workflow", "", "Workflow file or ID")
	ref := flag.String("ref", "main", "Target git ref")
	inputsJSON := flag.String("inputs", "{}", "JSON object string for workflow inputs")
	flag.Parse()

	if *owner == "" || *repo == "" || *workflow == "" {
		fmt.Fprintf(os.Stderr, "Error: owner, repo, and workflow are required\n")
		os.Exit(1)
	}

	token := os.Getenv("GH_TOKEN")
	if token == "" {
		fmt.Fprintf(os.Stderr, "Error: GH_TOKEN environment variable not set\n")
		os.Exit(1)
	}

	fmt.Printf("INFO: Trigger and Record\n")
	fmt.Printf("INFO:   Target: %s/%s\n", *owner, *repo)
	fmt.Printf("INFO:   Workflow: %s\n", *workflow)
	fmt.Printf("INFO:   Ref: %s\n", *ref)

	// Dispatch the workflow
	if err := dispatchWorkflow(token, *owner, *repo, *workflow, *ref, *inputsJSON); err != nil {
		fmt.Fprintf(os.Stderr, "Error dispatching workflow: %v\n", err)
		os.Exit(1)
	}

	// Wait for run to be registered
	fmt.Printf("INFO: Waiting 5s for run to be registered...\n")
	time.Sleep(5 * time.Second)

	// Find the run ID
	runID, err := findRunID(token, *owner, *repo, *workflow)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error finding run ID: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("INFO: Writing run_id=%s to GITHUB_OUTPUT\n", runID)
	// Write to GITHUB_OUTPUT
	if err := appendOutput("run_id", runID); err != nil {
		fmt.Fprintf(os.Stderr, "Error writing output: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("OK: Found workflow run: %s\n", runID)
}

func dispatchWorkflow(token, owner, repo, workflow, ref, inputsJSON string) error {
	url := fmt.Sprintf("https://api.github.com/repos/%s/%s/actions/workflows/%s/dispatches",
		owner, repo, workflow)

	// Parse inputs JSON
	var inputs map[string]interface{}
	if err := json.Unmarshal([]byte(inputsJSON), &inputs); err != nil {
		return fmt.Errorf("invalid inputs JSON: %w", err)
	}

	// Create dispatch request
	body := map[string]interface{}{
		"ref":    ref,
		"inputs": inputs,
	}
	bodyBytes, err := json.Marshal(body)
	if err != nil {
		return err
	}

	// Retry loop for dispatch
	for attempt := 1; attempt <= 5; attempt++ {
		fmt.Printf("INFO: [Dispatch attempt %d/5] POST %s\n", attempt, url)

		req, err := http.NewRequest("POST", url, bytes.NewReader(bodyBytes))
		if err != nil {
			return err
		}

		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", token))
		req.Header.Set("Accept", "application/vnd.github+json")
		req.Header.Set("Content-Type", "application/json")

		client := &http.Client{Timeout: 10 * time.Second}
		resp, err := client.Do(req)
		if err != nil {
			if attempt < 5 {
				delay := time.Duration(1<<uint(attempt-1)) * 2 * time.Second
				fmt.Printf("RETRY: Transient dispatch error, retrying in %v\n", delay)
				time.Sleep(delay)
				continue
			}
			return err
		}
		defer resp.Body.Close()

		if resp.StatusCode == 204 {
			fmt.Printf("INFO: Dispatch successful (HTTP 204)\n")
			fmt.Println("OK: Workflow dispatch triggered successfully")
			return nil
		}

		respBody, _ := io.ReadAll(resp.Body)

		if resp.StatusCode == 401 || resp.StatusCode == 403 || resp.StatusCode == 404 {
			return fmt.Errorf("non-retriable dispatch error (HTTP %d): %s", resp.StatusCode, string(respBody))
		}

		if attempt < 5 {
			delay := time.Duration(1<<uint(attempt-1)) * 2 * time.Second
			fmt.Printf("RETRY: Transient dispatch error (HTTP %d), retrying in %v\n", resp.StatusCode, delay)
			time.Sleep(delay)
			continue
		}

		return fmt.Errorf("dispatch failed after 5 attempts: HTTP %d: %s", resp.StatusCode, string(respBody))
	}

	return nil
}

func findRunID(token, owner, repo, workflow string) (string, error) {
	url := fmt.Sprintf("https://api.github.com/repos/%s/%s/actions/workflows/%s/runs?event=workflow_dispatch&per_page=5",
		owner, repo, workflow)

	for attempt := 1; attempt <= 8; attempt++ {
		fmt.Printf("INFO: [Find attempt %d/8] Fetching recent workflow runs...\n", attempt)

		req, err := http.NewRequest("GET", url, nil)
		if err != nil {
			return "", err
		}

		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", token))
		req.Header.Set("Accept", "application/vnd.github+json")

		client := &http.Client{Timeout: 10 * time.Second}
		resp, err := client.Do(req)
		if err != nil {
			if attempt < 8 {
				delay := time.Duration(1<<uint(attempt-1)) * 3 * time.Second
				fmt.Printf("RETRY: Transient lookup error, retrying in %v\n", delay)
				time.Sleep(delay)
				continue
			}
			return "", err
		}
		defer resp.Body.Close()

		if resp.StatusCode != 200 {
			respBody, _ := io.ReadAll(resp.Body)

			if resp.StatusCode == 401 || resp.StatusCode == 403 || resp.StatusCode == 404 {
				return "", fmt.Errorf("non-retriable lookup error (HTTP %d): %s", resp.StatusCode, string(respBody))
			}

			if attempt < 8 {
				delay := time.Duration(1<<uint(attempt-1)) * 3 * time.Second
				fmt.Printf("RETRY: Transient lookup error (HTTP %d), retrying in %v\n", resp.StatusCode, delay)
				time.Sleep(delay)
				continue
			}

			return "", fmt.Errorf("lookup failed after 8 attempts: HTTP %d: %s", resp.StatusCode, string(respBody))
		}

		var result struct {
			WorkflowRuns []struct {
				ID int64 `json:"id"`
			} `json:"workflow_runs"`
		}

		if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
			return "", err
		}

		if len(result.WorkflowRuns) > 0 {
			return fmt.Sprintf("%d", result.WorkflowRuns[0].ID), nil
		}

		if attempt < 8 {
			delay := time.Duration(1<<uint(attempt-1)) * 3 * time.Second
			fmt.Printf("RETRY: Run not yet registered, retrying in %v\n", delay)
			time.Sleep(delay)
			continue
		}

		return "", fmt.Errorf("could not find workflow run after 8 attempts")
	}

	return "", fmt.Errorf("failed to find run after 8 attempts")
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
