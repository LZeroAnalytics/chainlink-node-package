GO_IMAGE = "golang:1.21-alpine"

def generate_ocr3config(plan, input):
    """Generate OCR3 config using run_sh instead of persistent service"""
    
    # Upload source code
    ocr3_source = plan.upload_files(".")
    
    # Build an extract map dynamically so we get each signer/transmitter separately
    extract = {
        "signers_json":      "fromjson | .signers",
        "transmitters_json": "fromjson | .transmitters",
        "f":                 "fromjson | .f",
        "offchain_cfg_ver":  "fromjson | .offchainConfigVersion",
        "offchain_cfg":      "fromjson | .offchainConfig",
    }
    for i in range(len(input["nodes"])):
        extract["signer_{}".format(i)]      = "fromjson | .signers[{}]".format(i)
        extract["transmitter_{}".format(i)] = "fromjson | .transmitters[{}]".format(i)

    # Escape JSON for shell command
    escaped_json = json.encode(input).replace('"', '\\"').replace("'", "\\'")

    
    # Build and run in one command
    result = plan.run_sh(
        run = """
            cd /app && 
            go mod tidy && 
            go build -o ocr main.go && 
            ./ocr '{}'
        """.format(escaped_json),
        
        name = "ocr3-config-generator",
        image = GO_IMAGE,
        
        # Mount the source code
        files = {
            "/app": ocr3_source,
        },
        
        description = "Building and running OCR3 config generator",

        extract = extract
    )
    
    return result