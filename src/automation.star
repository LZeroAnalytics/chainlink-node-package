# Import packages
hardhat_package = import_module("github.com/LZeroAnalytics/hardhat-package/main.star")
deployment = import_module("./deployment.star")
node_utils = import_module("./node_utils.star")
constants = import_module("./package_io/constants.star")
ocr = import_module("./ocr/ocr.star")

def setup_automation_full(plan, network_cfg, automation_cfg):
    """Complete automation setup: nodes + contracts + configuration + jobs."""
    
    # 1. Deploy and fund nodes
    node_result = _deploy_and_fund_nodes(plan, network_cfg, automation_cfg)
    
    # 2. Configure OCR3 on registry (Automation v2.3 uses OCR3 under the hood)
    bootstrap_node, oracle_nodes, deployment_result = _deploy_and_config_automations2_3_contracts(plan, node_result, network_cfg, automation_cfg)
    
    # 3. Create jobs on nodes
    _create_automation_jobs(plan, network_cfg, automation_cfg, deployment_result["automationRegistry"], bootstrap_node, oracle_nodes)
    
    plan.print("Automation setup complete. Registry=" + deployment_result["automationRegistry"])
    return struct(
        addresses = deployment_result,
        nodes = node_result,
        bootstrap_node = bootstrap_node,
        oracle_nodes = oracle_nodes
    )


def _deploy_and_fund_nodes(plan, network_cfg, automation_cfg):
    """Deploy automation nodes and optionally fund them."""
    oracle_cnt = automation_cfg.get("oracle_nodes_count", 4)
    node_image = automation_cfg.get("node_image", constants.DEFAULT_CHAINLINK_IMAGE)
    
    configs = [{"node_name": "chainlink-node-automation-bootstrap", "image": node_image}]
    for i in range(oracle_cnt):
        configs.append({"node_name": "chainlink-node-automation-oracle-" + str(i), "image": node_image})
    
    node_result = deployment.deploy_nodes(plan, args = {"chains": [network_cfg], "chainlink_nodes": configs})
    
    # Fund nodes if faucet provided
    faucet_url = network_cfg.get("faucet", "")
    if faucet_url != "":
        for node_name in node_result.services.keys():
            eth_key = node_utils.get_eth_key(plan, node_name)
            node_utils.fund_eth_key(plan, eth_key, faucet_url)
    
    return node_result


def _deploy_and_config_automations2_3_contracts(plan, node_result, network_cfg, automation_cfg):
    hardhat_package.run(plan, "github.com/LZeroAnalytics/chainlink-automations-contracts", env_vars = {
        "RPC_URL": network_cfg.get("rpc", ""),
        "PRIVATE_KEY": network_cfg.get("private_key", ""),
        "CHAIN_ID": str(network_cfg.get("chain_id", 0)),
    })

    # Deploy full v2.3 stack (ForwarderLogic, LogicC/B/A, Registry, Registrar, feeds,…)
    deployment_result = hardhat_package.script(plan, "scripts/deploy-automation-v23.js", "bloctopus", 
        return_keys = {"registry": "automationRegistry", "registrar": "automationRegistrar"},
        extraCmds = " | grep -A 100 DEPLOYMENT_JSON_BEGIN | grep -B 100 DEPLOYMENT_JSON_END | sed '/DEPLOYMENT_JSON_BEGIN/d' | sed '/DEPLOYMENT_JSON_END/d'",
        params = {
            "NETWORK_TYPE": network_cfg.get("type", "ethereum"),
            "LINK_TOKEN_ADDRESS": automation_cfg.get("link_token_address", ""),
            "LINK_USD_FEED_ADDRESS": automation_cfg.get("link_usd_feed_address", ""),
            "NATIVE_USD_FEED_ADDRESS": automation_cfg.get("native_usd_feed_address", ""),
            "GAS_FEED_ADDRESS": automation_cfg.get("gas_feed_address", ""),
            "WRAPPED_NATIVE_ADDRESS": automation_cfg.get("wrapped_native_address", "")
        }
    )
    registry_addr = deployment_result["automationRegistry"]
    
    # 1. Extract node keys using existing node_utils
    bootstrap_node = "chainlink-node-automation-bootstrap"
    oracle_nodes = [name for name in node_result.services.keys() if "oracle" in name]
    all_nodes = [bootstrap_node] + oracle_nodes
    
    # Collect node information using existing patterns
    nodes_data = []
    for node_name in all_nodes:
        eth_key = node_utils.get_eth_key(plan, node_name)
        ocr_key = node_utils.get_ocr_key(plan, node_name)
        p2p_peer_id = node_utils.get_p2p_peer_id(plan, node_name)
        
        node_info = {
            "onchainKey": ocr_key.on_chain_key,
            "offchainKey": ocr_key.off_chain_key,
            "configKey": ocr_key.config_key,
            "peerID": p2p_peer_id,
            "transmitter": eth_key
        }
        nodes_data.append(node_info)
    
    # 3. Generate OCR3 config
    ocr3_input = { "nodes": nodes_data, "pluginType": "automation" }
    ocr3_result = ocr.generate_ocr3_config(plan, json.encode(ocr3_input))
    ocr3_config = json.decode(ocr3_result)
    
    # 4. Set config on registry using hardhat script with proper params
    f_value = str((len(all_nodes) - 1) / 3)  # Standard f calculation
    
    config_params = {
        "REGISTRY_ADDRESS": registry_addr,
        "SIGNERS": ",".join(ocr3_config["signers"]),
        "TRANSMITTERS": ",".join(ocr3_config["transmitters"]),
        "F_VALUE": f_value,
        "OFFCHAIN_CONFIG_VERSION": str(ocr3_config["offchainConfigVersion"]),
        "OFFCHAIN_CONFIG": ocr3_config["offchainConfig"],
        "REGISTRAR_ADDRESS": deployment_result["registrarAddress"],
        "CHAIN_MODULE_ADDRESS": deployment_result["chainModuleAddress"],
        "LINK_TOKEN_ADDRESS": deployment_result["linkTokenAddress"],
        "WRAPPED_NATIVE_ADDRESS": deployment_result["wrappedNativeAddress"],
        "LINK_USD_FEED_ADDRESS": deployment_result["linkUsdFeedAddress"],
        "NATIVE_USD_FEED_ADDRESS": deployment_result["nativeUsdFeedAddress"]
    }
    
    hardhat_package.script(
        plan, 
        "scripts/automations/set-automation-config-v23.js", 
        "bloctopus", 
        params = config_params
    )
    
    plan.print("OCR3 configuration completed successfully")
    return bootstrap_node, oracle_nodes, deployment_result


def _create_automation_jobs(plan, network_cfg, automation_cfg, registry_addr, bootstrap_node, oracle_nodes):
    """Create automation jobs on all nodes."""
    chain_id = network_cfg.get("chain_id", 0)
    contract_version = automation_cfg.get("contract_version", "v2.1+")
    mercury_url = automation_cfg.get("mercury", {}).get("url", "")
    
    # Bootstrap job
    node_utils.create_job(plan, bootstrap_node, "bootstrap-job-template.toml", {
        "BOOTSTRAP_CONTRACT_ADDRESS": registry_addr,
        "CHAIN_ID": str(chain_id)
    })
    
    # Oracle jobs
    bootstrap_peer = node_utils.get_p2p_peer_id(plan, bootstrap_node) + "@" + bootstrap_node + ":6689"
    
    for node_name in oracle_nodes:
        ocr2_key = node_utils.get_ocr_key_bundle_id(plan, node_name)
        transmitter = node_utils.get_eth_key(plan, node_name)
        
        node_utils.create_job(plan, node_name, "ocr2-automation-template.toml", {
            "REGISTRY_ADDRESS": registry_addr,
            "CHAIN_ID": str(chain_id),
            "OCR2_KEY_BUNDLE": ocr2_key,
            "TRANSMITTER_ADDRESS": transmitter,
            "BOOTSTRAP_PEERS": '"' + bootstrap_peer + '"',
            "CONTRACT_VERSION": contract_version,
            "MERCURY_URL": mercury_url
        })