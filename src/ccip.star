# ccip.star - Complete CCIP Network Setup

# Import packages
hardhat_package = import_module("github.com/LZeroAnalytics/hardhat-package/main.star")
main_package = import_module("../main.star")
node_utils = import_module("./node_utils.star")
constants = import_module("./package_io/constants.star")
ocr = import_module("./ocr/ocr.star")

def setup_ccip_full(plan, network_cfg, ccip_cfg):
    """Complete CCIP setup: nodes + contracts + configuration + jobs."""
    
    # 1. Deploy and fund nodes for both networks
    nodes_result = _deploy_and_fund_ccip_nodes(plan, network_cfg, ccip_cfg)
    
    # 2. Deploy chain-specific contracts on both networks
    contracts_result = _deploy_chain_contracts(plan, network_cfg, ccip_cfg)
    
    # 3. Deploy lane-specific contracts (OnRamp, OffRamp, CommitStore)
    lanes_result = _deploy_lane_contracts(plan, network_cfg, ccip_cfg, contracts_result)
    
    # 4. Configure OCR on commit and execution contracts
    ocr_result = _configure_ccip_ocr(plan, nodes_result, lanes_result, ccip_cfg)
    
    # 5. Create CCIP jobs on nodes
    jobs_result = _create_ccip_jobs(plan, nodes_result, lanes_result, ccip_cfg)
    
    plan.print("CCIP setup complete. Lanes configured between networks.")
    return struct(
        nodes = nodes_result,
        contracts = contracts_result,
        lanes = lanes_result,
        ocr_config = ocr_result,
        jobs = jobs_result
    )

def _deploy_and_fund_ccip_nodes(plan, network_cfg, ccip_cfg):
    """Deploy CCIP nodes for all networks."""
    oracle_cnt = ccip_cfg.get("oracle_nodes_count", 6)  # More nodes for CCIP
    node_image = ccip_cfg.get("node_image", constants.DEFAULT_CHAINLINK_IMAGE)
    
    # Create node configs for each network pair
    configs = []
    
    # Bootstrap nodes (one per network)
    for i, network in enumerate(network_cfg):
        configs.append({
            "node_name": f"chainlink-node-ccip-bootstrap-{network['name']}",
            "image": node_image
        })
    
    # Oracle nodes (shared across networks)
    for i in range(oracle_cnt):
        configs.append({
            "node_name": f"chainlink-node-ccip-oracle-{i}",
            "image": node_image
        })
    
    node_result = main_package.run(plan, args = {
        "network": network_cfg,
        "chainlink_nodes": configs
    })
    
    # Fund nodes on all networks
    for network in network_cfg:
        faucet_url = network.get("faucet", "")
        if faucet_url != "":
            for node_name in node_result.services.keys():
                eth_key = node_utils.get_eth_key(plan, node_name)
                node_utils.fund_eth_key(plan, eth_key, faucet_url)
    
    return node_result

def _deploy_chain_contracts(plan, network_cfg, ccip_cfg):
    """Deploy chain-specific contracts on each network."""
    contracts_by_network = {}
    
    for network in network_cfg:
        network_name = network["name"]
        chain_id = network["chain_id"]
        
        # Deploy common CCIP contracts for this chain
        deployment_result = hardhat_package.script(
            plan,
            "scripts/deploy-ccip-chain-contracts.js",
            "ccip-chain-" + network_name,
            return_keys = {
                "linkToken": "linkToken",
                "tokenAdminRegistry": "tokenAdminRegistry",
                "router": "router",
                "priceRegistry": "priceRegistry",
                "arm": "arm",
                "bridgeTokens": "bridgeTokens",
                "tokenPools": "tokenPools"
            },
            params = {
                "NETWORK_NAME": network_name,
                "CHAIN_ID": str(chain_id),
                "RPC_URL": network.get("rpc", ""),
                "PRIVATE_KEY": network.get("private_key", ""),
                "NO_OF_TOKENS": str(ccip_cfg.get("tokens_per_chain", 2)),
                "LINK_TOKEN_ADDRESS": ccip_cfg.get("existing_link_token", ""),
                "WRAPPED_NATIVE_ADDRESS": network.get("wrapped_native", "")
            }
        )
        
        contracts_by_network[network_name] = deployment_result
        
        plan.print(f"Chain contracts deployed on {network_name}")
        plan.print(f"  Router: {deployment_result['router']}")
        plan.print(f"  TokenAdminRegistry: {deployment_result['tokenAdminRegistry']}")
        plan.print(f"  PriceRegistry: {deployment_result['priceRegistry']}")
    
    return contracts_by_network

def _deploy_lane_contracts(plan, network_cfg, ccip_cfg, contracts_result):
    """Deploy lane-specific contracts (OnRamp, OffRamp, CommitStore)."""
    lanes = []
    
    # Create bidirectional lanes between network pairs
    network_pairs = _get_network_pairs(network_cfg, ccip_cfg)
    
    for pair in network_pairs:
        source_network = pair["source"]
        dest_network = pair["dest"]
        
        # Deploy forward lane (source -> dest)
        forward_lane = _deploy_single_lane(
            plan, source_network, dest_network, contracts_result, ccip_cfg
        )
        
        # Deploy reverse lane (dest -> source) if bidirectional
        reverse_lane = None
        if ccip_cfg.get("bidirectional", True):
            reverse_lane = _deploy_single_lane(
                plan, dest_network, source_network, contracts_result, ccip_cfg
            )
        
        lanes.append({
            "source_network": source_network["name"],
            "dest_network": dest_network["name"],
            "forward_lane": forward_lane,
            "reverse_lane": reverse_lane
        })
    
    return lanes

def _deploy_single_lane(plan, source_network, dest_network, contracts_result, ccip_cfg):
    """Deploy contracts for a single CCIP lane."""
    source_name = source_network["name"]
    dest_name = dest_network["name"]
    
    # Calculate chain selectors (you'll need your enhanced chain-selectors here)
    source_selector = _get_chain_selector(source_network["chain_id"])
    dest_selector = _get_chain_selector(dest_network["chain_id"])
    
    source_contracts = contracts_result[source_name]
    dest_contracts = contracts_result[dest_name]
    
    # Deploy OnRamp on source network
    onramp_result = hardhat_package.script(
        plan,
        "scripts/deploy-ccip-onramp.js",
        f"onramp-{source_name}-to-{dest_name}",
        return_keys = {"onRamp": "onRamp"},
        params = {
            "DEST_CHAIN_SELECTOR": str(dest_selector),
            "ROUTER_ADDRESS": source_contracts["router"],
            "TOKEN_ADMIN_REGISTRY": source_contracts["tokenAdminRegistry"],
            "RPC_URL": source_network.get("rpc", ""),
            "PRIVATE_KEY": source_network.get("private_key", "")
        }
    )
    
    # Deploy CommitStore and OffRamp on destination network
    dest_result = hardhat_package.script(
        plan,
        "scripts/deploy-ccip-offramp.js",
        f"offramp-{dest_name}-from-{source_name}",
        return_keys = {
            "commitStore": "commitStore",
            "offRamp": "offRamp"
        },
        params = {
            "SOURCE_CHAIN_SELECTOR": str(source_selector),
            "ROUTER_ADDRESS": dest_contracts["router"],
            "TOKEN_ADMIN_REGISTRY": dest_contracts["tokenAdminRegistry"],
            "RPC_URL": dest_network.get("rpc", ""),
            "PRIVATE_KEY": dest_network.get("private_key", "")
        }
    )
    
    # Update routers to include new ramps
    _update_router_ramps(plan, source_network, dest_selector, onramp_result["onRamp"], None)
    _update_router_ramps(plan, dest_network, source_selector, None, dest_result["offRamp"])
    
    return {
        "source_chain_selector": source_selector,
        "dest_chain_selector": dest_selector,
        "onramp": onramp_result["onRamp"],
        "commit_store": dest_result["commitStore"],
        "offramp": dest_result["offRamp"]
    }

def _configure_ccip_ocr(plan, nodes_result, lanes_result, ccip_cfg):
    """Configure OCR for CCIP commit and execution."""
    ocr_configs = []
    
    # Extract node information
    bootstrap_nodes = [name for name in nodes_result.services.keys() if "bootstrap" in name]
    oracle_nodes = [name for name in nodes_result.services.keys() if "oracle" in name]
    
    for lane in lanes_result:
        if lane["forward_lane"]:
            # Configure commit OCR
            commit_config = _configure_commit_ocr(
                plan, bootstrap_nodes[0], oracle_nodes, lane["forward_lane"], ccip_cfg
            )
            
            # Configure execution OCR
            exec_config = _configure_execution_ocr(
                plan, bootstrap_nodes[0], oracle_nodes, lane["forward_lane"], ccip_cfg
            )
            
            ocr_configs.append({
                "lane": f"{lane['source_network']}->{lane['dest_network']}",
                "commit_config": commit_config,
                "execution_config": exec_config
            })
    
    return ocr_configs

def _configure_commit_ocr(plan, bootstrap_node, oracle_nodes, lane, ccip_cfg):
    """Configure OCR for CCIP commit contract."""
    # Collect node information
    nodes_data = []
    all_nodes = [bootstrap_node] + oracle_nodes
    
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
    
    # Generate OCR config
    nodes_json = json.encode(nodes_data)
    ocr_result = ocr.generate_ocr2_config(plan, nodes_json)
    ocr_config = json.decode(ocr_result)
    
    # Set config on commit store
    hardhat_package.script(
        plan,
        "scripts/ccip/set-commit-store-config.js",
        f"commit-config-{lane['source_chain_selector']}-{lane['dest_chain_selector']}",
        params = {
            "COMMIT_STORE_ADDRESS": lane["commit_store"],
            "SIGNERS": ",".join(ocr_config["signers"]),
            "TRANSMITTERS": ",".join(ocr_config["transmitters"]),
            "F_VALUE": str((len(all_nodes) - 1) // 3),
            "OFFCHAIN_CONFIG_VERSION": str(ocr_config["offchainConfigVersion"]),
            "OFFCHAIN_CONFIG": ocr_config["offchainConfig"]
        }
    )
    
    return ocr_config

def _create_ccip_jobs(plan, nodes_result, lanes_result, ccip_cfg):
    """Create CCIP jobs on all nodes."""
    job_results = []
    
    bootstrap_nodes = [name for name in nodes_result.services.keys() if "bootstrap" in name]
    oracle_nodes = [name for name in nodes_result.services.keys() if "oracle" in name]
    
    for lane in lanes_result:
        if lane["forward_lane"]:
            forward_lane_info = lane["forward_lane"]
            
            # Create bootstrap jobs
            for bootstrap_node in bootstrap_nodes:
                _create_bootstrap_job(plan, bootstrap_node, forward_lane_info, ccip_cfg)
            
            # Create commit jobs
            for oracle_node in oracle_nodes:
                _create_commit_job(plan, oracle_node, forward_lane_info, bootstrap_nodes[0], ccip_cfg)
            
            # Create execution jobs  
            for oracle_node in oracle_nodes:
                _create_execution_job(plan, oracle_node, forward_lane_info, bootstrap_nodes[0], ccip_cfg)
            
            job_results.append({
                "lane": f"{lane['source_network']}->{lane['dest_network']}",
                "jobs_created": len(oracle_nodes) * 2 + len(bootstrap_nodes)  # commit + exec + bootstrap
            })
    
    return job_results

def _create_commit_job(plan, node_name, lane_info, bootstrap_node, ccip_cfg):
    """Create CCIP commit job on a node."""
    ocr2_key = node_utils.get_ocr_key_bundle_id(plan, node_name)
    transmitter = node_utils.get_eth_key(plan, node_name)
    bootstrap_peer = node_utils.get_p2p_peer_id(plan, bootstrap_node) + "@" + bootstrap_node + ":6689"
    
    node_utils.create_job(plan, node_name, "ccip-commit-job-template.toml", {
        "COMMIT_STORE_ADDRESS": lane_info["commit_store"],
        "OFFRAMP_ADDRESS": lane_info["offramp"],
        "SOURCE_CHAIN_SELECTOR": str(lane_info["source_chain_selector"]),
        "DEST_CHAIN_SELECTOR": str(lane_info["dest_chain_selector"]),
        "OCR2_KEY_BUNDLE": ocr2_key,
        "TRANSMITTER_ADDRESS": transmitter,
        "BOOTSTRAP_PEERS": '"' + bootstrap_peer + '"',
        "PLUGIN_TYPE": "ccipcommit"
    })

def _create_execution_job(plan, node_name, lane_info, bootstrap_node, ccip_cfg):
    """Create CCIP execution job on a node."""
    ocr2_key = node_utils.get_ocr_key_bundle_id(plan, node_name)
    transmitter = node_utils.get_eth_key(plan, node_name)
    bootstrap_peer = node_utils.get_p2p_peer_id(plan, bootstrap_node) + "@" + bootstrap_node + ":6689"
    
    node_utils.create_job(plan, node_name, "ccip-execution-job-template.toml", {
        "OFFRAMP_ADDRESS": lane_info["offramp"],
        "SOURCE_CHAIN_SELECTOR": str(lane_info["source_chain_selector"]),
        "DEST_CHAIN_SELECTOR": str(lane_info["dest_chain_selector"]),
        "OCR2_KEY_BUNDLE": ocr2_key,
        "TRANSMITTER_ADDRESS": transmitter,
        "BOOTSTRAP_PEERS": '"' + bootstrap_peer + '"',
        "PLUGIN_TYPE": "ccipexecution"
    })

# Helper functions
def _get_network_pairs(network_cfg, ccip_cfg):
    """Get network pairs for lane creation."""
    if len(network_cfg) < 2:
        fail("Need at least 2 networks for CCIP")
    
    # For now, create pairs between all networks
    pairs = []
    for i in range(len(network_cfg)):
        for j in range(i + 1, len(network_cfg)):
            pairs.append({
                "source": network_cfg[i],
                "dest": network_cfg[j]
            })
    
    return pairs

def _get_chain_selector(chain_id):
    """Get chain selector for chain ID - integrate with your enhanced chain-selectors."""
    # This would integrate with your enhanced chain-selectors
    # For now, using a simple mapping
    selector_map = {
        9388201: 16772745154982505732,  # Your custom chain A
        9250445: 15266224578806455440,  # Your custom chain B
        1: 5009297550715157269,         # Ethereum mainnet
        11155111: 16015286601757825753, # Sepolia
        42161: 4949039107694359620,     # Arbitrum One
        421614: 3478487238524512106     # Arbitrum Sepolia
    }
    
    return selector_map.get(chain_id, 0)

def _update_router_ramps(plan, network, dest_selector, onramp_addr, offramp_addr):
    """Update router with new ramp addresses."""
    params = {
        "RPC_URL": network.get("rpc", ""),
        "PRIVATE_KEY": network.get("private_key", ""),
        "ROUTER_ADDRESS": network.get("router_address", "")
    }
    
    if onramp_addr:
        params["DEST_CHAIN_SELECTOR"] = str(dest_selector)
        params["ONRAMP_ADDRESS"] = onramp_addr
        script_name = "scripts/ccip/update-router-onramps.js"
    else:
        params["SOURCE_CHAIN_SELECTOR"] = str(dest_selector)
        params["OFFRAMP_ADDRESS"] = offramp_addr
        script_name = "scripts/ccip/update-router-offramps.js"
    
    hardhat_package.script(plan, script_name, f"update-router-{network['name']}", params = params)
