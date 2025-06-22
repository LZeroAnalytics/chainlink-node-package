input_parser = import_module("./package_io/input_parser.star")
postgres = import_module("github.com/tiljrd/postgres-package/main.star")

def deploy_nodes(plan, args):
    # Parse the configuration
    config = input_parser.input_parser(plan, args)
    
    nodes_configs = {}
    for node in config.chainlink_nodes:
        # Create node database in postgres for each node
        postgres_output = create_node_database(plan, node.postgres, node.node_name) #TODO: parallelize login in postgres pakcage too to spin up multiple db at the same time
        nodes_configs[node.node_name] = create_node_config(plan, node, postgres_output, config.chains)

    #Deploy all nodes in parallel
    all_nodes = plan.add_services(
        configs = nodes_configs,
        description = "Deploying " + str(len(config.chainlink_nodes)) + " Chainlink nodes in parallel"
    )

    return struct(
        services = all_nodes,
        nodes_configs = config.chainlink_nodes
    )

# Create a ServiceConfig for a chainlink node without adding it
def create_node_config(plan, chainlink_configs, postgres_output, chains, capabilitiesRegistry=None):
    chains_for_template = []
    if chains != None and len(chains) > 0:
        for chain in chains:
            chains_for_template.append({
                "ChainID": str(chain["chain_id"]),
                "HTTPURL": chain["rpc"],
                "WSURL": chain["ws"]
            })

    config_subs = {
        "CHAINS": chains_for_template,
        "URL": postgres_output.url,
        "KEYSTORE_PW": chainlink_configs.keystore_pw,
        "CHAINLINK_API_PASSWORD": chainlink_configs.api_password,
        "CHAINLINK_API_EMAIL": chainlink_configs.api_user,
        "CAPABILITIES_REGISTRY_ADDRESS": capabilitiesRegistry,
        "HOME_CHAIN_ID": chains[0]["chain_id"],
    }

    # ---------- render node configs------------------------------------
    tomls_art = plan.render_templates(
        name   = "chainlink-tomls-" + chainlink_configs.node_name,
        config = {
            "/config.toml": struct(template = read_file("../templates/config.toml"), data = config_subs),
            "/secrets.toml": struct(template = read_file("../templates/secrets.toml"), data = config_subs),
            "/.api": struct(template = read_file("../templates/.api"), data = config_subs)
        },
    )

    # ---------- create node jobs templates artifacts-------------------------------------------
    jobs_templates_art = plan.upload_files( src = "../templates/jobs", name = "job-templates-"+chainlink_configs.node_name)

    return ServiceConfig(
        image = chainlink_configs.image,
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

def create_node_database(plan, postgres_configs, node_name):
    postgres_output = postgres.run(
        plan,
        service_name = "postgres-"+node_name,
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