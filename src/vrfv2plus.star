#Create bhs or bhf job on node
def create_bhs_or_bhf_job(plan, job_type, vrf_coordinator_address, blockhash_store_address, batch_blockhash_store_address, eth_address, chain_id, node_name):
    if job_type == "bhs":
        job_type_str = "blockhashstore"
    elif job_type == "bhf":
        job_type_str = "blockheaderfeeder"
    else:
        fail("Invalid job type: " + job_type)

    sed_cmd = "sed -i 's/{{.JOB_TYPE}}/%s/g; s/{{.VRF_COORDINATOR_ADDRESS}}/%s/g; s/{{.BLOCKHASH_STORE_ADDRESS}}/%s/g; s/{{.BATCH_BLOCKHASH_STORE_ADDRESS}}/%s/g; s/{{.ETH_ADDRESS}}/%s/g; s/{{.ChainID}}/%s/g;' /tmp/bhs-job.toml" % (
        job_type_str,
        vrf_coordinator_address,
        blockhash_store_address,
        batch_blockhash_store_address,
        eth_address,
        chain_id
    )

    cmd = [
        "chainlink admin login --file /chainlink/.api > /dev/null 2>&1 &&",
        "cp /templates/jobs/bhs-or-bhf-job-template.toml /tmp/bhs-job.toml &&",
        sed_cmd,
        "&& chainlink jobs create /tmp/bhs-job.toml"
    ]

    plan.exec(
        service_name = node_name,
        recipe = ExecRecipe(
            command = ["/bin/bash", "-c", " ".join(cmd)]
        )
    )

#Create vrfv2plus vrf job on node
def create_vrfv2plus_job(plan, vrf_coordinator_address, batch_coordinator_address, vrf_key, chain_id, eth_address, node_name):
    sed_cmd = "sed -i 's/{{.VRF_COORDINATOR_ADDRESS}}/%s/g; s/{{.VRF_BATCH_COORDINATOR_ADDRESS}}/%s/g; s/{{.VRF_KEY}}/%s/g; s/{{.CHAIN_ID}}/%s/g; s/{{.ETH_ADDRESS}}/%s/g;' /tmp/vrfv2plus-job.toml" % (
        vrf_coordinator_address,
        batch_coordinator_address,
        vrf_key,
        chain_id,
        eth_address
    )

    cmd = [
        "chainlink admin login --file /chainlink/.api > /dev/null 2>&1 &&",
        "cp /templates/jobs/vrfv2plus-job-template.toml /tmp/vrfv2plus-job.toml &&",
        sed_cmd,
        "&& chainlink jobs create /tmp/vrfv2plus-job.toml"
    ]

    plan.exec(
        service_name = node_name,
        recipe = ExecRecipe(
            command = ["/bin/bash", "-c", " ".join(cmd)]
        )
    )