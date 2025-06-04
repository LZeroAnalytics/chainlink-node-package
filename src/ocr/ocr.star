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