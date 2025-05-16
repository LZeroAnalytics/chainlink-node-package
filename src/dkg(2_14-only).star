### IMPORTANT WORKS ONLY WITH OLD V2.14.0 CHAINLINK VERSION - included for MPC VRF (ocr2vrf)

# Creates a DKG encryption key, returns the public key
def create_dkg_encr_key(plan, node_name):
    cmd = [
        "chainlink admin login --file /chainlink/.api > /dev/null 2>&1 &&",
        # Check version first - handle full version string with commit hash and architecture
        "if ! chainlink --version | grep -q '2.14.0'; then echo 'Version check failed' >&2; exit 1; fi &&",
        # emit {"eth":"<ADDRESS>"}  — one‑liner JSON
        "echo '{\"dkg_encr\":\"'$(chainlink keys dkgencrypt create | awk '/Public key:/ {print $3}' | head -n1)'\"}'"
    ]

    res = plan.exec(
        service_name = node_name,
        recipe = ExecRecipe(
            command  = ["/bin/bash", "-c", " ".join(cmd)],
            extract  = { "dkg_encr": "fromjson | .dkg_encr" },
        ),
    )

    return res["extract.dkg_encr"]

#Creates a DKG signing key, returns the public key
def create_dkg_sign_key(plan, node_name):
    cmd = [
        "chainlink admin login --file /chainlink/.api > /dev/null 2>&1 &&",
        # Check version first - handle full version string with commit hash and architecture
        "if ! chainlink --version | grep -q '2.14.0'; then echo 'Version check failed' >&2; exit 1; fi &&",
        # emit {"dkg_sign":"<ADDRESS>"}  — one‑liner JSON
        "echo '{\"dkg_sign\":\"'$(chainlink keys dkgsign create | awk '/Public key:/ {print $3}' | head -n1)'\"}'"
    ]

    res = plan.exec(
        service_name = node_name,
        recipe = ExecRecipe(
            command  = ["/bin/bash", "-c", " ".join(cmd)],
            extract  = { "dkg_sign": "fromjson | .dkg_sign" },
        ),
    )   

    return res["extract.dkg_sign"]

#Create DKG job on node (2.14 only)
def create_dkg_job(plan, job_name, dkg_contract_address, ocr_key_bundle_id, bootstrap_peer_id, bootstrap_peer_address, bootstrap_peer_port, eth_address, dkg_encryption_public_key, dkg_signing_public_key, dkg_key_id, chain_id, node_name):    
    # sub job template vars
    sed_cmd = "sed -i 's/{{.JOB_NAME}}/%s/g; s/{{.DKG_CONTRACT_ADDRESS}}/%s/g; s/{{.OCR_KEY_BUNDLE_ID}}/%s/g; s/{{.BOOTSTRAP_PEER_ID}}/%s/g; s/{{.BOOTSTRAP_PEER_ADDRESS}}/%s/g; s/{{.BOOTSTRAP_PEER_PORT}}/%s/g; s/{{.ETH_ADDRESS}}/%s/g; s/{{.CHAIN_ID}}/%s/g; s/{{.DKG_ENCRYPTION_PUBLIC_KEY}}/%s/g; s/{{.DKG_SIGNING_PUBLIC_KEY}}/%s/g; s/{{.DKG_KEY_ID}}/%s/g;' /tmp/dkg-job.toml" % (
        job_name,
        dkg_contract_address,
        ocr_key_bundle_id,
        bootstrap_peer_id,
        bootstrap_peer_address,
        bootstrap_peer_port,
        eth_address,
        chain_id,
        dkg_encryption_public_key,
        dkg_signing_public_key,
        dkg_key_id
    )
    
    cmd = [
        "chainlink admin login --file /chainlink/.api > /dev/null 2>&1 &&",
        # Check version first - handle full version string with commit hash and architecture
        "if ! chainlink --version | grep -q '2.14.0'; then echo 'Version check failed' >&2; exit 1; fi &&",
        "cp /templates/jobs/dkg-job-template.toml /tmp/dkg-job.toml &&",
        sed_cmd,
        "&& chainlink jobs create /tmp/dkg-job.toml"
    ]

    plan.exec(
        service_name = node_name,
        recipe = ExecRecipe(
            command = ["/bin/bash", "-c", " ".join(cmd)]
        )
    )