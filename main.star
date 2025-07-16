# Import the new package_io module
dkg = import_module("./src/dkg(2_14-only).star")
ocr2 = import_module("./src/ocr2vrf(2_14-only).star")
vrfv2plus = import_module("./src/vrfv2plus.star")
automations = import_module("./src/automation.star")
node_utils = import_module("./src/node_utils.star")
deployment = import_module("./src/deployment.star")
ocr = import_module("./src/ocr/ocr.star")
#Initialize chainlink node  
def run(plan, args = {}):
    return deployment.deploy_nodes(plan, args)