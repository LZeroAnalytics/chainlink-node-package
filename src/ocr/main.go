package main

import (
	"crypto/ed25519"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/ethereum/go-ethereum/common"
	ocr2keepers30config "github.com/smartcontractkit/chainlink-automation/pkg/v3/config"
	"github.com/smartcontractkit/libocr/offchainreporting2plus/confighelper"
	ocr3 "github.com/smartcontractkit/libocr/offchainreporting2plus/ocr3confighelper"
	"github.com/smartcontractkit/libocr/offchainreporting2plus/types"
)

type NodeInfo struct {
	OnchainKey  string `json:"onchainKey"`
	OffchainKey string `json:"offchainKey"`
	ConfigKey   string `json:"configKey"`
	PeerID      string `json:"peerID"`
	Transmitter string `json:"transmitter"`
}

type OCR3Config struct {
	Signers               []string `json:"signers"`
	Transmitters          []string `json:"transmitters"`
	F                     uint8    `json:"f"`
	OffchainConfigVersion uint64   `json:"offchainConfigVersion"`
	OffchainConfig        string   `json:"offchainConfig"`
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintf(os.Stderr, "Usage: %s <nodes_json>\n", os.Args[0])
		os.Exit(1)
	}

	// Parse input
	var nodes []NodeInfo
	if err := json.Unmarshal([]byte(os.Args[1]), &nodes); err != nil {
		fmt.Fprintf(os.Stderr, "Error parsing nodes JSON: %v\n", err)
		os.Exit(1)
	}

	// Build oracle identities using your libocr
	S := make([]int, len(nodes))
	oracleIdentities := make([]confighelper.OracleIdentityExtra, len(nodes))

	for i, node := range nodes {
		offchainPkBytes, _ := hex.DecodeString(strings.TrimPrefix(node.OffchainKey, "ocr2off_evm_"))
		configPkBytes, _ := hex.DecodeString(strings.TrimPrefix(node.ConfigKey, "ocr2cfg_evm_"))
		onchainPkBytes, _ := hex.DecodeString(strings.TrimPrefix(node.OnchainKey, "ocr2on_evm_"))

		var offchainPkFixed [ed25519.PublicKeySize]byte
		var configPkFixed [ed25519.PublicKeySize]byte
		copy(offchainPkFixed[:], offchainPkBytes)
		copy(configPkFixed[:], configPkBytes)

		oracleIdentities[i] = confighelper.OracleIdentityExtra{
			OracleIdentity: confighelper.OracleIdentity{
				OnchainPublicKey:  onchainPkBytes,
				OffchainPublicKey: offchainPkFixed,
				PeerID:            node.PeerID,
				TransmitAccount:   types.Account(node.Transmitter),
			},
			ConfigEncryptionPublicKey: configPkFixed,
		}
		S[i] = 1
	}

	// Automation plugin config (JSON for automation)
	automationConfig := ocr2keepers30config.OffchainConfig{
		TargetProbability:    "0.999",
		TargetInRounds:       1,
		PerformLockoutWindow: 100000,
		GasLimitPerReport:    10300000,
		GasOverheadPerUpkeep: 300_000,
		MinConfirmations:     0,
		MaxUpkeepBatchSize:   1,
	}
	pluginConfigBytes, _ := json.Marshal(automationConfig)

	// Generate proper OCR3 config using your libocr
	signers, transmitters, f, _, offchainConfigVersion, offchainConfig, err := ocr3.ContractSetConfigArgsForTests(
		30*time.Second,       // deltaProgress
		10*time.Second,       // deltaResend
		1*time.Second,        // deltaInitial
		1*time.Second,        // deltaRound
		500*time.Millisecond, // deltaGrace
		10*time.Second,       // deltaCertifiedCommitRequest
		60*time.Second,       // deltaStage
		3,                    // rMax
		S,
		oracleIdentities,
		pluginConfigBytes, // Real automation config
		nil,               // maxDurationInitialization
		20*time.Second,    // maxDurationQuery
		1*time.Second,     // maxDurationObservation
		10*time.Second,    // maxDurationShouldAcceptAttestedReport
		10*time.Second,    // maxDurationShouldTransmitAcceptedReport
		(len(nodes)-1)/3,  // f
		[]byte{},          // onchainConfig (set separately)
	)

	if err != nil {
		fmt.Fprintf(os.Stderr, "Error generating OCR3 config: %v\n", err)
		os.Exit(1)
	}

	// Convert to output format
	var signerAddrs, transmitterAddrs []string
	for _, signer := range signers {
		signerAddrs = append(signerAddrs, common.BytesToAddress(signer).Hex())
	}
	for _, transmitter := range transmitters {
		transmitterAddrs = append(transmitterAddrs, string(transmitter))
	}

	result := OCR3Config{
		Signers:               signerAddrs,
		Transmitters:          transmitterAddrs,
		F:                     f,
		OffchainConfigVersion: offchainConfigVersion,
		OffchainConfig:        hex.EncodeToString(offchainConfig),
	}

	output, _ := json.Marshal(result)
	fmt.Print(string(output))
}
