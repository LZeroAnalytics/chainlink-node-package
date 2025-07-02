GO_IMAGE = "golang:1.24-alpine"
GO_SERVICE_NAME = "ocr3-config-generator"

def init_ocr3_service(plan):
    """Initialize OCR3 service and build the binary once"""
    
    # Upload source code
    ocr3_source = plan.upload_files(".")
    
    # Add service 
    service = plan.add_service(
        name = GO_SERVICE_NAME,
        config = ServiceConfig(
            image = GO_IMAGE,
            files = {
                "/app": ocr3_source,
            },
            # Keep container running for exec commands
            entrypoint = ["tail", "-f", "/dev/null"]
        )
    )
    
    # Build the Go application inside the container
    plan.exec(
        service_name = GO_SERVICE_NAME,
        recipe = ExecRecipe(
            command = ["sh", "-c", "cd /app && go mod tidy && go build -o /usr/local/bin/ocr main.go"]
        )
    )
    
    return service

def generate_ocr3config(plan, input):
    """Generate OCR3 config using pre-built service"""
    
    # Build an extract map - create arrays directly instead of individual elements
    extract = {
        "signers":           "fromjson | [.signers[]]",      # Create array directly
        "transmitters":      "fromjson | [.transmitters[]]", # Create array directly
        "f":                 "fromjson | .f",
        "offchain_cfg_ver":  "fromjson | .offchainConfigVersion",
        "offchain_cfg":      "fromjson | .offchainConfig",
    }

    for i in range(len(input["nodes"])):
        extract["signer_{}".format(i)]      = "fromjson | .signers[{}]".format(i)
        extract["transmitter_{}".format(i)] = "fromjson | .transmitters[{}]".format(i)

    # Convert input to JSON string without additional escaping
    json_input = json.encode(input)

    # Run using pre-built binary
    result = plan.exec(
        service_name = GO_SERVICE_NAME,
        recipe = ExecRecipe(
            command = ["/usr/local/bin/ocr", json_input],
            extract = extract,
        ),
        description = "Running OCR3 config generator",
        
    )
    
    return result