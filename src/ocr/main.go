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
	"github.com/smartcontractkit/chainlink-ccip/pkg/types/ccipocr3"
	ccipconfig "github.com/smartcontractkit/chainlink-ccip/pluginconfig"
	commonconfig "github.com/smartcontractkit/chainlink-common/pkg/config"
	"github.com/smartcontractkit/libocr/offchainreporting2plus/confighelper"
	ocr3 "github.com/smartcontractkit/libocr/offchainreporting2plus/ocr3confighelper"
	"github.com/smartcontractkit/libocr/offchainreporting2plus/types"
	"golang.org/x/crypto/curve25519"
)

// Plugin types enum
type PluginType string

const (
	PluginTypeAutomation PluginType = "automation"
	PluginTypeCommit     PluginType = "commit"
	PluginTypeExec       PluginType = "exec"
)

type NodeInfo struct {
	OnchainKey  string `json:"onchainKey"`
	OffchainKey string `json:"offchainKey"`
	ConfigKey   string `json:"configKey"`
	PeerID      string `json:"peerID"`
	Transmitter string `json:"transmitter"`
}

// Unified input structure
type UnifiedInput struct {
	Nodes      []NodeInfo `json:"nodes"`
	PluginType PluginType `json:"pluginType"`
	// CCIP specific fields (optional for automation)
	ChainSelector     string `json:"chainSelector,omitempty"`
	FeedChainSelector string `json:"feedChainSelector,omitempty"`
}

type OCR3Config struct {
	Signers               []string `json:"signers"`
	Transmitters          []string `json:"transmitters"`
	F                     uint8    `json:"f"`
	OffchainConfigVersion uint64   `json:"offchainConfigVersion"`
	OffchainConfig        string   `json:"offchainConfig"`
	ConfigDigest          string   `json:"configDigest,omitempty"`
}

// We'll use the types directly from chainlink-ccip/pluginconfig

// Add stripKeyPrefix function to match official implementation
func stripKeyPrefix(key string) string {
	// Remove common prefixes
	prefixes := []string{"ocr2off_evm_", "ocr2cfg_evm_", "ocr2on_evm_", "0x"}
	result := key
	for _, prefix := range prefixes {
		result = strings.TrimPrefix(result, prefix)
	}
	return result
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintf(os.Stderr, "Usage: %s <unified_input_json>\n", os.Args[0])
		os.Exit(1)
	}

	// Parse unified input
	var input UnifiedInput
	if err := json.Unmarshal([]byte(os.Args[1]), &input); err != nil {
		fmt.Fprintf(os.Stderr, "Error parsing input JSON: %v\n", err)
		os.Exit(1)
	}

	// Build oracle identities - matching official implementation
	S := make([]int, len(input.Nodes))
	oracleIdentities := make([]confighelper.OracleIdentityExtra, len(input.Nodes))

	for i, node := range input.Nodes {
		// Process keys following official implementation pattern
		offChainPubKeyTemp, err := hex.DecodeString(stripKeyPrefix(node.OffchainKey))
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error decoding offchain key for node %d: %v\n", i, err)
			os.Exit(1)
		}

		configPubKeyTemp, err := hex.DecodeString(stripKeyPrefix(node.ConfigKey))
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error decoding config key for node %d: %v\n", i, err)
			os.Exit(1)
		}

		// For onchain key, use the official method: convert to address first, then get bytes
		formattedOnChainPubKey := stripKeyPrefix(node.OnchainKey)
		onchainPkBytes := common.HexToAddress(formattedOnChainPubKey).Bytes()

		// Fix array sizes and copying
		var offchainPkFixed [ed25519.PublicKeySize]byte
		var configPkFixed [curve25519.PointSize]byte
		copy(offchainPkFixed[:], offChainPubKeyTemp)
		copy(configPkFixed[:], configPubKeyTemp)

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

	// Generate config based on plugin type
	config, err := generateConfigForPlugin(input, oracleIdentities, S)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error generating config: %v\n", err)
		os.Exit(1)
	}

	output, _ := json.Marshal(config)
	fmt.Print(string(output))
}

func generateConfigForPlugin(input UnifiedInput, oracleIdentities []confighelper.OracleIdentityExtra, S []int) (*OCR3Config, error) {
	var pluginConfigBytes []byte
	var err error
	var timingParams OCRTimingParams

	// Generate plugin-specific config and timing
	switch input.PluginType {
	case PluginTypeAutomation:
		automationConfig := ocr2keepers30config.OffchainConfig{
			TargetProbability:    "0.999",
			TargetInRounds:       1,
			PerformLockoutWindow: 3600000, // Milliseconds
			GasLimitPerReport:    5300000,
			GasOverheadPerUpkeep: 300000,
			MinConfirmations:     0,
			MaxUpkeepBatchSize:   1,
		}
		pluginConfigBytes, err = json.Marshal(automationConfig)
		timingParams = getAutomationTimingParams()

	case PluginTypeCommit:
		commitConfig := getCommitConfig()
		pluginConfigBytes, err = json.Marshal(commitConfig)
		timingParams = getCommitTimingParams()

	case PluginTypeExec:
		execConfig := getExecConfig()
		pluginConfigBytes, err = json.Marshal(execConfig)
		timingParams = getExecTimingParams()

	default:
		return nil, fmt.Errorf("unsupported plugin type: %s", input.PluginType)
	}

	if err != nil {
		return nil, fmt.Errorf("marshal plugin config: %w", err)
	}

	// Generate OCR3 config with plugin-specific parameters
	signers, transmitters, f, _, offchainConfigVersion, offchainConfig, err := ocr3.ContractSetConfigArgsForTests(
		timingParams.DeltaProgress,
		timingParams.DeltaResend,
		timingParams.DeltaInitial,
		timingParams.DeltaRound,
		timingParams.DeltaGrace,
		timingParams.DeltaCertifiedCommitRequest,
		timingParams.DeltaStage,
		timingParams.RMax,
		S,
		oracleIdentities,
		pluginConfigBytes,
		timingParams.MaxDurationInitialization,
		timingParams.MaxDurationQuery,
		timingParams.MaxDurationObservation,
		timingParams.MaxDurationShouldAcceptAttestedReport,
		timingParams.MaxDurationShouldTransmitAcceptedReport,
		(len(input.Nodes)-1)/3, // f
		[]byte{},               // onchainConfig
	)

	if err != nil {
		return nil, fmt.Errorf("generate OCR3 config: %w", err)
	}

	return convertToOCR3Config(signers, transmitters, f, offchainConfigVersion, offchainConfig, input.PluginType)
}

type OCRTimingParams struct {
	DeltaProgress                           time.Duration
	DeltaResend                             time.Duration
	DeltaInitial                            time.Duration
	DeltaRound                              time.Duration
	DeltaGrace                              time.Duration
	DeltaCertifiedCommitRequest             time.Duration
	DeltaStage                              time.Duration
	RMax                                    uint64
	MaxDurationInitialization               *time.Duration
	MaxDurationQuery                        time.Duration
	MaxDurationObservation                  time.Duration
	MaxDurationShouldAcceptAttestedReport   time.Duration
	MaxDurationShouldTransmitAcceptedReport time.Duration
}

// Timing parameters based on Go globals
func getCommitTimingParams() OCRTimingParams {
	return OCRTimingParams{
		DeltaProgress:                           30 * time.Second, //120 * time.Second,
		DeltaResend:                             10 * time.Second, //30 * time.Second,
		DeltaInitial:                            20 * time.Second,
		DeltaRound:                              2 * time.Second, //6 * time.Second,
		DeltaGrace:                              2 * time.Second, //5 * time.Second,
		DeltaCertifiedCommitRequest:             10 * time.Second,
		DeltaStage:                              10 * time.Second, //25 * time.Second,
		RMax:                                    10,               //3
		MaxDurationInitialization:               nil,
		MaxDurationQuery:                        10 * time.Second, //7 * time.Second,
		MaxDurationObservation:                  13 * time.Second,
		MaxDurationShouldAcceptAttestedReport:   5 * time.Second,
		MaxDurationShouldTransmitAcceptedReport: 10 * time.Second,
	}
}

func getExecTimingParams() OCRTimingParams {
	return OCRTimingParams{
		DeltaProgress:                           30 * time.Second, //120 * time.Second,
		DeltaResend:                             10 * time.Second, //30 * time.Second,
		DeltaInitial:                            20 * time.Second,
		DeltaRound:                              2 * time.Second, //6 * time.Second,
		DeltaGrace:                              2 * time.Second, //5 * time.Second,
		DeltaCertifiedCommitRequest:             10 * time.Second,
		DeltaStage:                              10 * time.Second, //25 * time.Second,
		RMax:                                    10,               //3
		MaxDurationInitialization:               nil,
		MaxDurationQuery:                        100 * time.Millisecond, // exec doesn't use query
		MaxDurationObservation:                  13 * time.Second,
		MaxDurationShouldAcceptAttestedReport:   5 * time.Second,
		MaxDurationShouldTransmitAcceptedReport: 10 * time.Second,
	}
}

func getAutomationTimingParams() OCRTimingParams {
	return OCRTimingParams{
		DeltaProgress:                           30 * time.Second,
		DeltaResend:                             10 * time.Second,
		DeltaInitial:                            1 * time.Second,
		DeltaRound:                              1 * time.Second,
		DeltaGrace:                              500 * time.Millisecond,
		DeltaCertifiedCommitRequest:             10 * time.Second,
		DeltaStage:                              60 * time.Second,
		RMax:                                    3,
		MaxDurationInitialization:               nil,
		MaxDurationQuery:                        20 * time.Second,
		MaxDurationObservation:                  1 * time.Second,
		MaxDurationShouldAcceptAttestedReport:   10 * time.Second,
		MaxDurationShouldTransmitAcceptedReport: 10 * time.Second,
	}
}

// Default commit config
func getCommitConfig() ccipconfig.CommitOffchainConfig {
	return ccipconfig.CommitOffchainConfig{
		RemoteGasPriceBatchWriteFrequency:  *commonconfig.MustNewDuration(10 * time.Minute),
		TokenPriceBatchWriteFrequency:      *commonconfig.MustNewDuration(1 * time.Hour),
		NewMsgScanBatchSize:                128,
		MaxReportTransmissionCheckAttempts: 3,
		RMNEnabled:                         false,
		RMNSignaturesTimeout:               10 * time.Minute,
		MaxMerkleTreeSize:                  128,
		SignObservationPrefix:              "ccip 1.6 rmn",
		TransmissionDelayMultiplier:        10 * time.Second,
		InflightPriceCheckRetries:          5,
		MerkleRootAsyncObserverDisabled:    true,
		MerkleRootAsyncObserverSyncFreq:    0,
		MerkleRootAsyncObserverSyncTimeout: 0,
		ChainFeeAsyncObserverDisabled:      true,
		ChainFeeAsyncObserverSyncFreq:      0,
		ChainFeeAsyncObserverSyncTimeout:   0,
		TokenPriceAsyncObserverDisabled:    true,
		TokenPriceAsyncObserverSyncFreq:    *commonconfig.MustNewDuration(0),
		TokenPriceAsyncObserverSyncTimeout: *commonconfig.MustNewDuration(0),
		PriceFeedChainSelector:             0, // Will be set from input.ChainSelector
		TokenInfo:                          make(map[ccipocr3.UnknownEncodedAddress]ccipconfig.TokenInfo),
	}
}

// Default exec config
func getExecConfig() ccipconfig.ExecuteOffchainConfig {
	return ccipconfig.ExecuteOffchainConfig{
		BatchGasLimit:               5000000,
		InflightCacheExpiry:         *commonconfig.MustNewDuration(30 * time.Second),
		RootSnoozeTime:              *commonconfig.MustNewDuration(2 * time.Minute),
		MessageVisibilityInterval:   *commonconfig.MustNewDuration(30 * time.Minute),
		BatchingStrategyID:          0,
		TransmissionDelayMultiplier: 10 * time.Second,
		MaxReportMessages:           10,
		MaxSingleChainReports:       10,
		TokenDataObservers:          []ccipconfig.TokenDataObserverConfig{},
	}
}

func convertToOCR3Config(signers []types.OnchainPublicKey, transmitters []types.Account, f uint8, offchainConfigVersion uint64, offchainConfig []byte, pluginType PluginType) (*OCR3Config, error) {
	var signerAddrs, transmitterAddrs []string

	for _, signer := range signers {
		signerAddrs = append(signerAddrs, common.BytesToAddress(signer[:]).Hex())
	}

	for _, transmitter := range transmitters {
		transmitterAddrs = append(transmitterAddrs, string(transmitter))
	}

	config := &OCR3Config{
		Signers:               signerAddrs,
		Transmitters:          transmitterAddrs,
		F:                     f,
		OffchainConfigVersion: offchainConfigVersion,
		OffchainConfig:        hex.EncodeToString(offchainConfig),
	}

	// Only add config digest for CCIP plugins
	if pluginType == PluginTypeCommit || pluginType == PluginTypeExec {
		configDigest := fmt.Sprintf("0x%x", offchainConfig[:32])
		if len(offchainConfig) < 32 {
			configDigest = fmt.Sprintf("0x%064x", len(offchainConfig))
		}
		config.ConfigDigest = configDigest
	}

	return config, nil
}
