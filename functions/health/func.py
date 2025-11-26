"""
Health Check Function

Simple health check endpoint for Load Balancer health probes.
Returns 200 OK with status information.
"""

import io
import json
import logging

from fdk import response
from datetime import datetime, timezone

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def handler(ctx, data: io.BytesIO = None):
    """
    Health check endpoint.

    Returns simple JSON response for LB health probes.
    """
    return response.Response(
        ctx,
        response_data=json.dumps({
            "status": "healthy",
            "timestamp": datetime.now(timezone.utc).isoformat()
        }),
        status_code=200,
        headers={"Content-Type": "application/json"}
    )
