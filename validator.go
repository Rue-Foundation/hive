package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/fsouza/go-dockerclient"
	"gopkg.in/inconshreveable/log15.v2"
)

// validateClients runs a batch of validation tests matched by validatorPattern
// against all clients matching clientPattern.
func validateClients(daemon *docker.Client, clientPattern, validatorPattern string, overrides []string) (bool, error) {
	// Build all the clients matching the validation pattern
	log15.Info("building clients for validation", "pattern", clientPattern)
	clients, err := buildClients(daemon, clientPattern)
	if err != nil {
		return false, err
	}
	// Build all the validators known to the test harness
	log15.Info("building validators for testing", "pattern", validatorPattern)
	validators, err := buildValidators(daemon, validatorPattern)
	if err != nil {
		return false, err
	}
	// Iterate over all client and validator combos and cross-execute them
	results := make(map[string]map[string][]string)
	anyFailed := false

	for client, clientImage := range clients {
		results[client] = make(map[string][]string)

		for validator, validatorImage := range validators {
			logger := log15.New("client", client, "validator", validator)

			logdir := filepath.Join(hiveLogsFolder, "validations", fmt.Sprintf("%s[%s]", strings.Replace(validator, "/", ":", -1), client))
			os.RemoveAll(logdir)

			start := time.Now()
			if pass, err := validate(daemon, clientImage, validatorImage, overrides, logger, logdir); pass {
				logger.Info("validation passed", "time", time.Since(start))
				results[client]["pass"] = append(results[client]["pass"], validator)
			} else {
				anyFailed = true
				logger.Error("validation failed", "time", time.Since(start))
				fail := validator
				if err != nil {
					fail += ": " + err.Error()
				}
				results[client]["fail"] = append(results[client]["fail"], fail)
			}
		}
	}
	// Print the validation logs
	out, _ := json.MarshalIndent(results, "", "  ")
	fmt.Printf("Validation results:\n%s\n", string(out))

	return anyFailed, nil
}

func validate(daemon *docker.Client, client, validator string, overrides []string, logger log15.Logger, logdir string) (bool, error) {
	logger.Info("running client validation")

	// Create the client container and make sure it's cleaned up afterwards
	logger.Debug("creating client container")
	cc, err := createClientContainer(daemon, client, validator, nil, overrides, nil)
	if err != nil {
		logger.Error("failed to create client", "error", err)
		return false, err
	}
	clogger := logger.New("id", cc.ID[:8])
	clogger.Debug("created client container")
	defer func() {
		clogger.Debug("deleting client container")
		daemon.RemoveContainer(docker.RemoveContainerOptions{ID: cc.ID, Force: true})
	}()

	// Start the client container and retrieve its IP address for the validator
	clogger.Debug("running client container")
	cwaiter, err := runContainer(daemon, cc.ID, clogger, filepath.Join(logdir, "client.log"), false)
	if err != nil {
		clogger.Error("failed to run client", "error", err)
		return false, err
	}
	defer cwaiter.Close()

	lcc, err := daemon.InspectContainer(cc.ID)
	if err != nil {
		clogger.Error("failed to retrieve client IP", "error", err)
		return false, err
	}
	cip := lcc.NetworkSettings.IPAddress

	// Wait for the HTTP/RPC socket to open or the container to fail
	start := time.Now()
	for {
		// If the container died, bail out
		c, err := daemon.InspectContainer(cc.ID)
		if err != nil {
			clogger.Error("failed to inspect client", "error", err)
			return false, err
		}
		if !c.State.Running {
			clogger.Error("client container terminated")
			return false, errors.New("terminated unexpectedly")
		}
		// Container seems to be alive, check whether the RPC is accepting connections
		if conn, err := net.Dial("tcp", fmt.Sprintf("%s:%d", c.NetworkSettings.IPAddress, 8545)); err == nil {
			clogger.Debug("client container online", "time", time.Since(start))
			conn.Close()
			break
		}
		time.Sleep(100 * time.Millisecond)
	}
	// Create the validator container and make sure it's cleaned up afterwards
	logger.Debug("creating validator container")
	vc, err := daemon.CreateContainer(docker.CreateContainerOptions{
		Config: &docker.Config{
			Image: validator,
			Env:   []string{"HIVE_CLIENT_IP=" + cip},
		},
	})
	if err != nil {
		logger.Error("failed to create validator", "error", err)
		return false, err
	}
	vlogger := logger.New("id", vc.ID[:8])
	vlogger.Debug("created validator container")
	defer func() {
		vlogger.Debug("deleting validator container")
		daemon.RemoveContainer(docker.RemoveContainerOptions{ID: vc.ID, Force: true})
	}()

	// Start the tester container and wait until it finishes
	vlogger.Debug("running validator container")
	vwaiter, err := runContainer(daemon, vc.ID, vlogger, filepath.Join(logdir, "validator.log"), false)
	if err != nil {
		vlogger.Error("failed to run validator", "error", err)
		return false, err
	}
	vwaiter.Wait()

	// Retrieve the exist status to report pass of fail
	v, err := daemon.InspectContainer(vc.ID)
	if err != nil {
		vlogger.Error("failed to inspect validator", "error", err)
		return false, err
	}
	return v.State.ExitCode == 0, nil
}
