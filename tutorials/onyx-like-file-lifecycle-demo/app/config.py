from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    postgres_url: str = "postgresql+psycopg2://demo:demo@postgres:5432/demo"
    redis_broker_url: str = "redis://:redispass@redis:6379/15"
    redis_result_backend_url: str = "redis://:redispass@redis:6379/16"
    minio_endpoint: str = "http://minio:9000"
    minio_access_key: str = "minioadmin"
    minio_secret_key: str = "minioadmin123"
    minio_bucket: str = "demo-files"
    region_name: str = "us-east-1"
    # Add a small delay so DELETING status is visible in UI while worker runs.
    simulated_delete_delay_seconds: int = 3


settings = Settings()
