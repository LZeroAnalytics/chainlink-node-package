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

// Complete CCIP Commit Plugin Configuration (matching Go pluginconfig.CommitOffchainConfig)
type CCIPCommitOffchainConfig struct {
	RemoteGasPriceBatchWriteFrequency  time.Duration        `json:"remoteGasPriceBatchWriteFrequency"`
	TokenPriceBatchWriteFrequency      time.Duration        `json:"tokenPriceBatchWriteFrequency"`
	NewMsgScanBatchSize                uint32               `json:"newMsgScanBatchSize"`
	MaxReportTransmissionCheckAttempts uint32               `json:"maxReportTransmissionCheckAttempts"`
	RMNEnabled                         bool                 `json:"rmnEnabled"`
	RMNSignaturesTimeout               time.Duration        `json:"rmnSignaturesTimeout"`
	MaxMerkleTreeSize                  uint32               `json:"maxMerkleTreeSize"`
	SignObservationPrefix              string               `json:"signObservationPrefix"`
	TransmissionDelayMultiplier        time.Duration        `json:"transmissionDelayMultiplier"`
	InflightPriceCheckRetries          uint32               `json:"inflightPriceCheckRetries"`
	MerkleRootAsyncObserverDisabled    bool                 `json:"merkleRootAsyncObserverDisabled"`
	MerkleRootAsyncObserverSyncFreq    time.Duration        `json:"merkleRootAsyncObserverSyncFreq"`
	MerkleRootAsyncObserverSyncTimeout time.Duration        `json:"merkleRootAsyncObserverSyncTimeout"`
	ChainFeeAsyncObserverDisabled      bool                 `json:"chainFeeAsyncObserverDisabled"`
	TokenPriceAsyncObserverDisabled    bool                 `json:"tokenPriceAsyncObserverDisabled"`
	PriceFeedChainSelector             string               `json:"priceFeedChainSelector"`
	TokenInfo                          map[string]TokenInfo `json:"tokenInfo"`
}

type TokenInfo struct {
	Symbol   string `json:"symbol"`
	Decimals uint8  `json:"decimals"`
}

// Complete CCIP Execute Plugin Configuration (matching Go pluginconfig.ExecuteOffchainConfig)
type CCIPExecuteOffchainConfig struct {
	BatchGasLimit               uint32                    `json:"batchGasLimit"`
	InflightCacheExpiry         time.Duration             `json:"inflightCacheExpiry"`
	RootSnoozeTime              time.Duration             `json:"rootSnoozeTime"`
	MessageVisibilityInterval   time.Duration             `json:"messageVisibilityInterval"`
	BatchingStrategyID          uint32                    `json:"batchingStrategyID"`
	TransmissionDelayMultiplier time.Duration             `json:"transmissionDelayMultiplier"`
	MaxReportMessages           uint32                    `json:"maxReportMessages"`
	MaxSingleChainReports       uint32                    `json:"maxSingleChainReports"`
	TokenDataObservers          []TokenDataObserverConfig `json:"tokenDataObservers"`
}

type TokenDataObserverConfig struct {
	Type string `json:"type"`
	// Additional fields would be added based on observer type
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

	// Build oracle identities
	S := make([]int, len(input.Nodes))
	oracleIdentities := make([]confighelper.OracleIdentityExtra, len(input.Nodes))

	for i, node := range input.Nodes {
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
			PerformLockoutWindow: 100000,
			GasLimitPerReport:    10300000,
			GasOverheadPerUpkeep: 300_000,
			MinConfirmations:     0,
			MaxUpkeepBatchSize:   1,
		}
		pluginConfigBytes, err = json.Marshal(automationConfig)
		timingParams = getAutomationTimingParams()

	case PluginTypeCommit:
		commitConfig := getCommitConfig(input)
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

// Default commit config based on Go globals.DefaultCommitOffChainCfg
func getCommitConfig(input UnifiedInput) CCIPCommitOffchainConfig {
	return CCIPCommitOffchainConfig{
		RemoteGasPriceBatchWriteFrequency:  20 * time.Minute, // ethprod: 2 * time.Hour
		TokenPriceBatchWriteFrequency:      2 * time.Hour,    //eth prod: 12 * time.Hour
		NewMsgScanBatchSize:                256,              // merklemulti.MaxNumberTreeLeaves
		MaxReportTransmissionCheckAttempts: 5,                //prod: 10
		RMNEnabled:                         false,            //true for prod envs (but we do not have rmn here)
		RMNSignaturesTimeout:               30 * time.Minute, // ethprod: 6900 * time.Millisecond
		MaxMerkleTreeSize:                  256,              // merklemulti.MaxNumberTreeLeaves
		SignObservationPrefix:              "chainlink ccip 1.6 rmn observation",
		TransmissionDelayMultiplier:        15 * time.Second,
		InflightPriceCheckRetries:          10,
		MerkleRootAsyncObserverDisabled:    false,
		MerkleRootAsyncObserverSyncFreq:    4 * time.Second,
		MerkleRootAsyncObserverSyncTimeout: 12 * time.Second,
		ChainFeeAsyncObserverDisabled:      true,
		TokenPriceAsyncObserverDisabled:    true,
		PriceFeedChainSelector:             input.FeedChainSelector,
		TokenInfo:                          make(map[string]TokenInfo),
	}
}

// Default exec config based on Go globals.DefaultExecuteOffChainCfg
func getExecConfig() CCIPExecuteOffchainConfig {
	config := CCIPExecuteOffchainConfig{
		BatchGasLimit:               6_500_000,
		InflightCacheExpiry:         1 * time.Minute,
		RootSnoozeTime:              5 * time.Minute,
		MessageVisibilityInterval:   1 * time.Hour, //wth prod: 8 hours
		BatchingStrategyID:          0,
		TransmissionDelayMultiplier: 15 * time.Second,
		MaxReportMessages:           0,
		MaxSingleChainReports:       0,
		TokenDataObservers:          []TokenDataObserverConfig{},
	}
	return config
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
