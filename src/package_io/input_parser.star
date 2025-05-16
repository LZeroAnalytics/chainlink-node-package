constants = import_module("./constants.star")
sanity_check = import_module("./sanity_check.star")

def input_parser(plan, input_args):
    """Parse and validate input arguments for the Chainlink package"""
    
    # Run sanity check first
    sanity_check.sanity_check(plan, input_args)
    
    # Get default configuration
    result = default_input_args()
    
    # Parse network config
    if "network" in input_args:
        for key, value in input_args["network"].items():
            result["network"][key] = value
    
    # Parse chainlink nodes config
    if "chainlink_nodes" in input_args and type(input_args["chainlink_nodes"]) == "list":
        # Replace the default node with specified nodes
        result["chainlink_nodes"] = []
        
        for node_config in input_args["chainlink_nodes"]:
            # Start with a new default node for each entry
            node_result = default_node_config()
            
            # Parse node-specific configs
            for key, value in node_config.items():
                if key == "postgres" and type(value) == "dict":
                    for pg_key, pg_value in value.items():
                        node_result["postgres"][pg_key] = pg_value
                else:
                    node_result[key] = value
                    
            # Add to nodes list
            result["chainlink_nodes"].append(node_result)
    
    # Validate configuration
    validate_config(result)
    
    # Convert to structs for immutability
    nodes_structs = []
    for node in result["chainlink_nodes"]:
        nodes_structs.append(
            struct(
                node_name = node["node_name"],
                image_version = node["image_version"],
                keystore_pw = node["keystore_pw"],
                api_user = node["api_user"],
                api_password = node["api_password"],
                postgres = struct(
                    user = node["postgres"]["user"],
                    password = node["postgres"]["password"],
                    min_cpu = node["postgres"]["min_cpu"],
                    max_cpu = node["postgres"]["max_cpu"],
                    min_memory = node["postgres"]["min_memory"],
                    max_memory = node["postgres"]["max_memory"],
                ),
            )
        )
    
    # Create a struct with parsed configs
    return struct(
        network = struct(
            rpc = result["network"]["rpc"],
            ws = result["network"]["ws"],
            chain_id = result["network"]["chain_id"],
        ),
        chainlink_nodes = nodes_structs
    )

def default_input_args():
    """Return default configuration values"""
    
    return {
        "network": {
            "rpc": "",
            "ws": "",
            "chain_id": "",
        },
        "chainlink_nodes": []
    }

def validate_config(config):
    """Validate the configuration"""
    # Validate Network config
    if not config["network"]["rpc"]:
        fail("network.rpc is required")
    if not config["network"]["ws"]:
        fail("network.ws is required")
    if not config["network"]["chain_id"]:
        fail("network.chain_id is required")
    
    # Validate Chainlink nodes config
    if len(config["chainlink_nodes"]) == 0:
        fail("At least one chainlink node is required")
    
    # Validate each node configuration
    for i, node in enumerate(config["chainlink_nodes"]):
        node_label = "chainlink_nodes[{0}]".format(i)
        
        if not node["node_name"]:
            fail("{0}.node_name is required".format(node_label))
        if not node["image_version"]:
            fail("{0}.image_version is required".format(node_label))
        if len(node["keystore_pw"]) < 16:
            fail("{0}.keystore_pw must be at least 16 characters".format(node_label))
        if not node["api_user"]:
            fail("{0}.api_user is required".format(node_label))
        if not node["api_password"]:
            fail("{0}.api_password is required".format(node_label))

def default_node_config():
    """Return a default node configuration"""
    return {
        "node_name": "chainlink-node",
        "image_version": constants.DEFAULT_CHAINLINK_IMAGE_VERSION,
        "keystore_pw": constants.DEFAULT_KEYSTORE_PW,
        "api_user": constants.DEFAULT_CHAINLINK_API_USER,
        "api_password": constants.DEFAULT_CHAINLINK_API_PASSWORD,
        "postgres": {
            "user": "postgres",
            "password": constants.DEFAULT_POSTGRES_PASSWORD,
            "min_cpu": constants.POSTGRES_RESOURCES.min_cpu,
            "max_cpu": constants.POSTGRES_RESOURCES.max_cpu,
            "min_memory": constants.POSTGRES_RESOURCES.min_memory,
            "max_memory": constants.POSTGRES_RESOURCES.max_memory,
        }
    } 