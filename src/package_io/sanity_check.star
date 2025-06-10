# These are the only allowed fields in the config.yaml
CHAIN_CONFIG_PARAMS = [
    "type",
    "rpc",
    "ws",
    "chain_id"
]

CHAINLINK_NODE_PARAMS = [
    "node_name",
    "image",
    "keystore_pw",
    "api_user",
    "api_password",
    "postgres"
]

POSTGRES_CONFIG_PARAMS = [
    "user",
    "password",
    "min_cpu",
    "max_cpu",
    "min_memory",
    "max_memory",
]

def sanity_check(plan, input_args):
    """Validate input arguments for the Chainlink package"""
    # Check network config fields
    if "chains" in input_args:
        for chain in input_args["chains"]:
            validate_params(plan, chain, "chains", CHAIN_CONFIG_PARAMS)
    
    # Check chainlink nodes configuration
    if "chainlink_nodes" in input_args:
        if type(input_args["chainlink_nodes"]) != "list":
            fail("chainlink_nodes must be a list")
        
        for i, node_config in enumerate(input_args["chainlink_nodes"]):
            node_category = "chainlink_nodes[{0}]".format(i)
            validate_params(plan, node_config, node_category, CHAINLINK_NODE_PARAMS, exclude_nested=True)
            
            # Check postgres config if present
            if "postgres" in node_config:
                postgres_category = "{0}.postgres".format(node_category)
                validate_params(plan, node_config["postgres"], postgres_category, POSTGRES_CONFIG_PARAMS)
              
    plan.print("Chainlink package sanity check passed")

def validate_params(plan, config, category, allowed_params, exclude_nested=False):
    """Validate parameters against allowed list"""
    for param in config:
        # Skip nested objects if exclude_nested is True
        if exclude_nested and type(config[param]) == "dict":
            continue
            
        if param not in allowed_params:
            fail(
                "Invalid parameter '{0}' for {1}. Allowed fields: {2}".format(
                    param, category, allowed_params
                )
            ) 