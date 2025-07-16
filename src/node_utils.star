# Node utility functions for Chainlink nodes

def get_p2p_peer_id(plan, node_name):
    """Reads first P2P key and returns its libp2p PeerID string."""
    cmd = [
        "chainlink admin login --file /chainlink/.api > /dev/null 2>&1 &&",
        # produce {"peer":"<ID>"} on stdout
        "echo '{\"peer\":\"'$(chainlink keys p2p list | awk '/Peer ID:/ {print substr($3,5)}' | head -n1)'\"}'"
    ]

    res = plan.exec(
        service_name = node_name,
        recipe = ExecRecipe(
            command = ["/bin/bash", "-c", " ".join(cmd)],
            extract = { "peer": "fromjson | .peer" }
        )
    )

    return res["extract.peer"]


def get_eth_key(plan, node_name, chain_id=None):
    """Returns EVM key address for specified chain ID or by index if no chain ID provided."""
    if chain_id:
        # Get key for specific chain ID deterministically
        cmd = [
            "chainlink admin login --file /chainlink/.api > /dev/null 2>&1 &&",
            # Filter by chain ID and extract address
            "echo '{\"eth\":\"'$(chainlink keys eth list | awk '/Address:/ {addr=$2} /EVM Chain ID:[[:space:]]*%s/ {print addr}')'\"}'" % chain_id
        ]
    else:
        # Fallback to index-based selection (original behavior)
        cmd = [
            "chainlink admin login --file /chainlink/.api > /dev/null 2>&1 &&",
            # emit {"eth":"<ADDRESS>"}
            "echo '{\"eth\":\"'$(chainlink keys eth list | awk '/Address:/ {print $2}' | head -n1)'\"}'"
        ]

    res = plan.exec(
        service_name = node_name,
        recipe = ExecRecipe(
            command  = ["/bin/bash", "-c", " ".join(cmd)],
            extract  = { "eth": "fromjson | .eth" },
        ),
    )

    return res["extract.eth"]


def get_ocr_key_bundle_id(plan, node_name):
    """Gets OCR key bundle ID."""
    cmd = [
        "chainlink admin login --file /chainlink/.api > /dev/null 2>&1 &&",
        # emit {"ocr_key_bundle_id":"<ID>"}  — one‑liner JSON
        "echo '{\"ocr_key_bundle_id\":\"'$(chainlink keys ocr2 list | awk '/ID:/ {print $2}' | head -n1)'\"}'"
    ]

    res = plan.exec(
        service_name = node_name,
        recipe = ExecRecipe(
            command  = ["/bin/bash", "-c", " ".join(cmd)],
            extract  = { "ocr_key_bundle_id": "fromjson | .ocr_key_bundle_id" },
        ),
    )   

    return res["extract.ocr_key_bundle_id"]


def get_ocr_key(plan, node_name):
    """Gets OCR key details (on-chain, off-chain, and config keys)."""
    cmd = [
        "chainlink admin login --file /chainlink/.api > /dev/null 2>&1 &&", # quiet login
        "echo '{\"on_chain_key\":\"0x'$(chainlink keys ocr2 list | awk '/On-chain pubkey:/ {print substr($3,12)}')'\",",
        "\"off_chain_key\":\"'$(chainlink keys ocr2 list | awk '/Off-chain pubkey:/ {print substr($3,13)}')'\",", 
        "\"config_key\":\"'$(chainlink keys ocr2 list | awk '/Config pubkey:/ {print substr($3,13)}')'\"}'"
    ]
    
    result = plan.wait(
        service_name = node_name,
        recipe = ExecRecipe(
            command  = ["/bin/bash", "-c", " ".join(cmd)],
            extract  = { 
                "on_chain_key": "fromjson | .on_chain_key",
                "off_chain_key": "fromjson | .off_chain_key",
                "config_key": "fromjson | .config_key"
            },
        ),
        field = "code",
        assertion = "==",
        target_value = 0,
        interval = "5s",
        timeout = "30s",
        description = "waiting for OCR key command to succeed"
    )
    
    return struct(
        on_chain_key = result["extract.on_chain_key"],
        off_chain_key = result["extract.off_chain_key"],
        config_key = result["extract.config_key"]
    )


def fund_eth_key(plan, eth_key, faucet_url):
    """Send 1 native coin to `eth_key` via simple faucet HTTP POST."""
    result = plan.run_sh(
        name = "fund-link-node-eth-wallet",
        image = "curlimages/curl:latest",
        run = "curl -X POST " + faucet_url + "/fund -H 'Content-Type: application/json' -d '{\"address\":\"" + eth_key + "\",\"amount\":1}'"
    )
    
    return result.code


def create_bootstrap_job(plan, dkg_contract_address, chain_id, node_name):
    """Create a DKG bootstrap job on the specified node."""
    cmd = [
        "chainlink admin login --file /chainlink/.api > /dev/null 2>&1 &&",
        "cp /templates/jobs/dkg-bootstrap-job-template.toml /tmp/bootstrap-job.toml &&",
        "sed -i 's/{{.DKG_CONTRACT_ADDRESS}}/%s/g; s/{{.CHAIN_ID}}/%s/g;' /tmp/bootstrap-job.toml" % (dkg_contract_address, chain_id),
        "&& chainlink jobs create /tmp/bootstrap-job.toml"
    ]

    plan.exec(
        service_name = node_name,
        recipe = ExecRecipe(
            command = ["/bin/bash", "-c", " ".join(cmd)]
        )
    )

def _seed_read_only_admin(plan, api_user, api_password, node_name):
    cmd = [
        "chainlink", "admin", "users", "create",
        "--api-email", api_user,
        "--api-password", api_password,
        "--role", "admin"
    ]
    
    plan.exec(
        service_name = node_name,
        recipe = ExecRecipe(
            command = ["/bin/bash", "-c", " ".join(cmd)]
        )
    )

def create_job(plan, node_name, template_name, substitutions):
    """Create a job from template with dynamic key-value substitutions."""
    
    # Build sed command dynamically from substitutions dictionary
    sed_replacements = []
    for key, value in substitutions.items():
        sed_replacements.append("s/{{.%s}}/%s/g" % (key, value))
    
    sed_cmd = "sed -i '%s' /tmp/%s.toml" % ("; ".join(sed_replacements), template_name)
    
    cmd = [
        "chainlink admin login --file /chainlink/.api > /dev/null 2>&1 &&",
        "cp /templates/jobs/%s /tmp/%s.toml &&" % (template_name, template_name),
        sed_cmd,
        "&& chainlink jobs create /tmp/%s.toml" % template_name
    ]
    plan.exec(service_name = node_name, recipe = ExecRecipe(command = ["/bin/bash", "-c", " ".join(cmd)]))