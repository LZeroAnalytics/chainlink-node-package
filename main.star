# Import the new package_io module
input_parser = import_module("./src/package_io/input_parser.star")
postgres = import_module("github.com/tiljrd/postgres-package/main.star")
dkg = import_module("./src/dkg(2_14-only).star")
ocr2 = import_module("./src/ocr2vrf(2_14-only).star")
vrfv2plus = import_module("./src/vrfv2plus.star")

#Initialize chainlink node
def run(plan, args = {}):
    # Parse the configuration
    config = input_parser.input_parser(plan, args)
    
    nodes_configs = {}
    for node in config.chainlink_nodes:
        # Create node database in postgres for each node
        postgres_output = create_node_database(plan, node.postgres, node.node_name) #TODO: parallelize login in postgres pakcage too to spin up multiple db at the same time
        nodes_configs[node.node_name] = create_node_config(plan, node, postgres_output, config.network)

    #Deploy all nodes in parallel
    all_nodes = plan.add_services(
        configs = nodes_configs,
        description = "Deploying " + str(len(config.chainlink_nodes)) + " Chainlink nodes in parallel"
    )

    return struct(
        services = all_nodes,
        nodes_configs = config.chainlink_nodes
    )


def create_node_database(plan, postgres_configs, node_name):
    postgres_output = postgres.run(
        plan,
        service_name = "postgres-chainlink-"+node_name,
        user = postgres_configs.user,
        password = postgres_configs.password,
        min_cpu = postgres_configs.min_cpu,
        max_cpu = postgres_configs.max_cpu,
        min_memory = postgres_configs.min_memory,
        max_memory = postgres_configs.max_memory,
        extra_env_vars = {
            "POSTGRES_INITDB_ARGS": "-E UTF8 --locale=C"
        }
    )

    return postgres_output


# Create a ServiceConfig for a chainlink node without adding it
def create_node_config(plan, chainlink_configs, postgres_output, chain_configs):
    config_subs = {
        "CHAIN_ID":    chain_configs.chain_id,
        "RPC_URL":    chain_configs.rpc,
        "WS_URL":     chain_configs.ws,
        "URL":    postgres_output.url,
        "KEYSTORE_PW": chainlink_configs.keystore_pw,
        "CHAINLINK_API_PASSWORD": chainlink_configs.api_password,
        "CHAINLINK_API_EMAIL": chainlink_configs.api_user,
    }

    # ---------- render node configs------------------------------------
    tomls_art = plan.render_templates(
        name   = "chainlink-tomls-" + chainlink_configs.node_name,
        config = {
            "/config.toml": struct(template = read_file("./templates/config.toml"), data = config_subs),
            "/secrets.toml": struct(template = read_file("./templates/secrets.toml"), data = config_subs),
            "/.api": struct(template = read_file("./templates/.api"), data = config_subs)
        },
    )

    # ---------- create node jobs templates artifacts-------------------------------------------
    jobs_templates_art = plan.upload_files( src = "./templates/jobs", name = "job-templates-"+chainlink_configs.node_name)

    return ServiceConfig(
        image = "smartcontract/chainlink:"+chainlink_configs.image_version,
        files = { 
            "/chainlink": tomls_art, 
            "/templates/jobs": jobs_templates_art
        },
        ports = {
            "http": PortSpec(6688, "TCP"),
            "p2p": PortSpec(6689, "TCP"),
        },
        entrypoint = [
            "chainlink","node",
            "-config",  "/chainlink/config.toml",
            "-secrets", "/chainlink/secrets.toml",
            "start",
            "-a", "/chainlink/.api",
        ],
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

# creates vrfv2plus key on node and returns public key
def create_vrf_keys(plan, node_name): #this cmd should be uneccessary, only works with v2 vrf, now vrf key si created with DKG and automatically smbitted on chain in the coordinator address
    cmd = [
        "chainlink admin login --file /chainlink/.api > /dev/null 2>&1 &&",
        # Convert to JSON format
        "echo '{' && chainlink keys vrf create | grep -E '^(Compressed|Uncompressed)' | sed -e 's/^ *//' -e 's/\\(.*\\): *\\(.*\\)/\"\\1\": \"\\2\"/' | sed -e '1s/^/  /' -e '2s/^/  /' -e '1s/$/,/' && echo '}'",
    ]
    
    result = plan.exec(
        service_name = node_name,
        recipe = ExecRecipe(
            command = ["/bin/bash", "-c", " ".join(cmd)],
            extract = {
                "compressed": "fromjson | .Compressed",
                "uncompressed": "fromjson | .Uncompressed"
            }
        )
    )

    return struct(
        compressed = result["extract.compressed"],
        uncompressed = result["extract.uncompressed"]
    )

# reads first P2P key and returns its libp2p PeerID string.
def get_p2p_peer_id(plan, node_name):
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

# returns first EVM key address (used by node to sign on-chain transactions)
def get_eth_key(plan, node_name):
    cmd = [
        "chainlink admin login --file /chainlink/.api > /dev/null 2>&1 &&",
        # emit {"eth":"<ADDRESS>"}  — one‑liner JSON
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

#Gets OCR key bundle ID
def get_ocr_key_bundle_id(plan, node_name):
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
    
    return struct  (
        on_chain_key = result["extract.on_chain_key"],
        off_chain_key = result["extract.off_chain_key"],
        config_key = result["extract.config_key"]
    )

def create_bootstrap_job(plan, dkg_contract_address, chain_id, node_name):
    
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