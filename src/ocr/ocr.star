GO_IMAGE = "golang:1.21-alpine"

def generate_ocr3config(plan, nodes_json):
    """Generate OCR3 config using run_sh instead of persistent service"""
    
    # Upload source code
    ocr3_source = plan.upload_files("./ocr")
    
    # Escape JSON for shell command
    escaped_json = nodes_json.replace('"', '\\"').replace("'", "\\'")
    
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
    )
    
    return result.output

def generate_ccip_ocr3_config(plan, nodes_json):
    """Generate CCIP-specific OCR3 config for commit/exec plugins.
    
    This function is specifically for CCIP and uses the enhanced main.go
    that supports commit and exec plugin types with proper timing parameters.
    """
    
    # Upload source code with CCIP support
    ocr3_source = plan.upload_files("./ocr")
    
    # Escape JSON for shell command
    escaped_json = nodes_json.replace('"', '\\"').replace("'", "\\'")
    
    # Build and run CCIP OCR3 config generator
    # Note: The main.go already supports commit and exec plugins
    result = plan.run_sh(
        run = """
            cd /app && 
            go mod tidy && 
            go build -o ocr main.go && 
            ./ocr '{}'
        """.format(escaped_json),
        
        name = "ccip-ocr3-config-generator",
        image = GO_IMAGE,
        
        # Mount the source code
        files = {
            "/app": ocr3_source,
        },
        
        description = "Building and running CCIP OCR3 config generator",
    )
    
    return result.output