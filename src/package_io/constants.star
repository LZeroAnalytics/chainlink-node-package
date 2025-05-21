# Service types
SERVICE_TYPE = struct(
    chainlink="chainlink",
    postgres="postgres",
)

# Default images
DEFAULT_CHAINLINK_IMAGE = "smartcontract/chainlink:2.23.0"

# Default credentials
DEFAULT_KEYSTORE_PW = "T.tLHkcmwePT/p,]sYuntjwHKAsrhm#4eRs4LuKHwvHejWYAC2JP4M8HimDgCqZ5"
DEFAULT_CHAINLINK_API_USER = "admin@chain.link"
DEFAULT_CHAINLINK_API_PASSWORD = "Ku8Qp4xKq#GmK@fyNq7T"
DEFAULT_POSTGRES_PASSWORD = "MyPassword123456!"

# Resource limits
POSTGRES_RESOURCES = struct(
    min_cpu = 10,
    max_cpu = 1000,
    min_memory = 32,
    max_memory = 1024,
)