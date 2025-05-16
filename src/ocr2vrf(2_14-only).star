#Create ocr2 job on node (2.14 only)
def create_ocr2vrf_job(plan, job_name, vrf_beacon_address, ocr_key_bundle_id, eth_address, bootstrap_peer_id, bootstrap_peer_address, bootstrap_peer_port, chain_id, dkg_encryption_public_key, dkg_signing_public_key, dkg_key_id, dkg_contract_address, vrf_coordinator_address, link_eth_feed_address, node_name):
    # sub job template vars
    sed_cmd = "sed -i 's/{{.JOB_NAME}}/%s/g; s/{{.VRF_BEACON_ADDRESS}}/%s/g; s/{{.OCR_KEY_BUNDLE_ID}}/%s/g; s/{{.ETH_ADDRESS}}/%s/g; s/{{.BOOTSTRAP_PEER_ID}}/%s/g; s/{{.BOOTSTRAP_PEER_ADDRESS}}/%s/g; s/{{.BOOTSTRAP_PEER_PORT}}/%s/g; s/{{.CHAIN_ID}}/%s/g; s/{{.DKG_ENCRYPTION_PUBLIC_KEY}}/%s/g; s/{{.DKG_SIGNING_PUBLIC_KEY}}/%s/g; s/{{.DKG_KEY_ID}}/%s/g; s/{{.DKG_CONTRACT_ADDRESS}}/%s/g; s/{{.VRF_COORDINATOR_ADDRESS}}/%s/g; s/{{.LINK_ETH_FEED_ADDRESS}}/%s/g;' /tmp/ocr2vrf-job.toml" % (
        job_name, vrf_beacon_address, ocr_key_bundle_id, eth_address, bootstrap_peer_id, bootstrap_peer_address, bootstrap_peer_port, chain_id, dkg_encryption_public_key, dkg_signing_public_key, dkg_key_id, dkg_contract_address, vrf_coordinator_address, link_eth_feed_address)
    
    cmd = [
        "chainlink admin login --file /chainlink/.api > /dev/null 2>&1 &&",
        # Check version first - handle full version string with commit hash and architecture
        "if ! chainlink --version | grep -q '2.14.0'; then echo 'Version check failed' >&2; exit 1; fi &&",
        "cp /templates/jobs/ocr2vrf-job-template.toml /tmp/ocr2vrf-job.toml &&",
        sed_cmd,
        "&& chainlink jobs create /tmp/ocr2vrf-job.toml"
    ]

    plan.exec(
        service_name = node_name,
        recipe = ExecRecipe(
            command = ["/bin/bash", "-c", " ".join(cmd)]
        )
    )