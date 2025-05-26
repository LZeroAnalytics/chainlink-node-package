# Utility functions for creating various Chainlink job types

# Create OCR job on node
def create_ocr_job(plan, job_name, contract_address, p2p_peer_id, bootstrap_peer_id, bootstrap_peer_address, bootstrap_peer_port, is_bootstrap, ocr_key_bundle_id, monitoring_endpoint, eth_address, fetch_url, parse_path, multiply_factor, external_job_id, chain_id, node_name):
    sed_cmd = "sed -i 's/{{.JOB_NAME}}/%s/g; s/{{.CONTRACT_ADDRESS}}/%s/g; s/{{.P2P_PEER_ID}}/%s/g; s/{{.BOOTSTRAP_PEER_ID}}/%s/g; s/{{.BOOTSTRAP_PEER_ADDRESS}}/%s/g; s/{{.BOOTSTRAP_PEER_PORT}}/%s/g; s/{{.IS_BOOTSTRAP}}/%s/g; s/{{.OCR_KEY_BUNDLE_ID}}/%s/g; s/{{.MONITORING_ENDPOINT}}/%s/g; s/{{.ETH_ADDRESS}}/%s/g; s/{{.FETCH_URL}}/%s/g; s/{{.PARSE_PATH}}/%s/g; s/{{.MULTIPLY_FACTOR}}/%s/g; s/{{.EXTERNAL_JOB_ID}}/%s/g; s/{{.CHAIN_ID}}/%s/g;' /tmp/ocr-job.toml" % (
        job_name,
        contract_address,
        p2p_peer_id,
        bootstrap_peer_id,
        bootstrap_peer_address,
        bootstrap_peer_port,
        is_bootstrap,
        ocr_key_bundle_id,
        monitoring_endpoint,
        eth_address,
        fetch_url,
        parse_path,
        multiply_factor,
        external_job_id,
        chain_id
    )
    
    cmd = [
        "chainlink admin login --file /chainlink/.api > /dev/null 2>&1 &&",
        "cp /templates/jobs/ocr-job-template.toml /tmp/ocr-job.toml &&",
        sed_cmd,
        "&& chainlink jobs create /tmp/ocr-job.toml"
    ]
    
    plan.exec(
        service_name = node_name,
        recipe = ExecRecipe(
            command = ["/bin/bash", "-c", " ".join(cmd)]
        )
    )

# Create Direct Request job on node
def create_direct_request_job(plan, job_name, operator_address, external_job_id, parse_path, chain_id, node_name):
    sed_cmd = "sed -i 's/{{.JOB_NAME}}/%s/g; s/{{.OPERATOR_ADDRESS}}/%s/g; s/{{.EXTERNAL_JOB_ID}}/%s/g; s/{{.PARSE_PATH}}/%s/g; s/{{.CHAIN_ID}}/%s/g;' /tmp/direct-request-job.toml" % (
        job_name,
        operator_address,
        external_job_id,
        parse_path,
        chain_id
    )
    
    cmd = [
        "chainlink admin login --file /chainlink/.api > /dev/null 2>&1 &&",
        "cp /templates/jobs/direct-request-job-template.toml /tmp/direct-request-job.toml &&",
        sed_cmd,
        "&& chainlink jobs create /tmp/direct-request-job.toml"
    ]
    
    plan.exec(
        service_name = node_name,
        recipe = ExecRecipe(
            command = ["/bin/bash", "-c", " ".join(cmd)]
        )
    )

# Create Cron job on node
def create_cron_job(plan, job_name, cron_schedule, function_signature, target_contract, chain_id, node_name):
    sed_cmd = "sed -i 's/{{.JOB_NAME}}/%s/g; s/{{.CRON_SCHEDULE}}/%s/g; s/{{.FUNCTION_SIGNATURE}}/%s/g; s/{{.TARGET_CONTRACT}}/%s/g; s/{{.CHAIN_ID}}/%s/g;' /tmp/cron-job.toml" % (
        job_name,
        cron_schedule,
        function_signature,
        target_contract,
        chain_id
    )
    
    cmd = [
        "chainlink admin login --file /chainlink/.api > /dev/null 2>&1 &&",
        "cp /templates/jobs/cron-job-template.toml /tmp/cron-job.toml &&",
        sed_cmd,
        "&& chainlink jobs create /tmp/cron-job.toml"
    ]
    
    plan.exec(
        service_name = node_name,
        recipe = ExecRecipe(
            command = ["/bin/bash", "-c", " ".join(cmd)]
        )
    )

# Create Keeper job on node
def create_keeper_job(plan, job_name, keeper_registry_address, eth_address, chain_id, node_name):
    sed_cmd = "sed -i 's/{{.JOB_NAME}}/%s/g; s/{{.KEEPER_REGISTRY_ADDRESS}}/%s/g; s/{{.ETH_ADDRESS}}/%s/g; s/{{.CHAIN_ID}}/%s/g;' /tmp/keeper-job.toml" % (
        job_name,
        keeper_registry_address,
        eth_address,
        chain_id
    )
    
    cmd = [
        "chainlink admin login --file /chainlink/.api > /dev/null 2>&1 &&",
        "cp /templates/jobs/keeper-job-template.toml /tmp/keeper-job.toml &&",
        sed_cmd,
        "&& chainlink jobs create /tmp/keeper-job.toml"
    ]
    
    plan.exec(
        service_name = node_name,
        recipe = ExecRecipe(
            command = ["/bin/bash", "-c", " ".join(cmd)]
        )
    )

# Create Webhook job on node
def create_webhook_job(plan, job_name, parse_path, function_signature, function_params, target_contract, chain_id, node_name):
    sed_cmd = "sed -i 's/{{.JOB_NAME}}/%s/g; s/{{.PARSE_PATH}}/%s/g; s/{{.FUNCTION_SIGNATURE}}/%s/g; s/{{.FUNCTION_PARAMS}}/%s/g; s/{{.TARGET_CONTRACT}}/%s/g; s/{{.CHAIN_ID}}/%s/g;' /tmp/webhook-job.toml" % (
        job_name,
        parse_path,
        function_signature,
        function_params,
        target_contract,
        chain_id
    )
    
    cmd = [
        "chainlink admin login --file /chainlink/.api > /dev/null 2>&1 &&",
        "cp /templates/jobs/webhook-job-template.toml /tmp/webhook-job.toml &&",
        sed_cmd,
        "&& chainlink jobs create /tmp/webhook-job.toml"
    ]
    
    plan.exec(
        service_name = node_name,
        recipe = ExecRecipe(
            command = ["/bin/bash", "-c", " ".join(cmd)]
        )
    )

# Trigger a webhook job via HTTP
def trigger_webhook_job(plan, node_name, job_id, payload):
    cmd = [
        "chainlink admin login --file /chainlink/.api > /dev/null 2>&1 &&",
        "curl -X POST -H 'Content-Type: application/json' -d '%s' http://localhost:6688/v2/jobs/%s/runs" % (
            payload.replace("'", "\\'"),
            job_id
        )
    ]
    
    plan.exec(
        service_name = node_name,
        recipe = ExecRecipe(
            command = ["/bin/bash", "-c", " ".join(cmd)]
        )
    )
