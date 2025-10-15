# =============================================================================
# API Monitoring Wrapper Module
# =============================================================================
# This module provides wrappers for API calls that include connection pool monitoring

from time import time
from monitoring.connection_pool_integration import ConnectionPoolIntegration
from core.logger import get_logger

fn wrap_api_call(component: String, integration: ConnectionPoolIntegration, api_func, *args, **kwargs):
    """
    Wrap an API call with connection pool monitoring

    Args:
        component: Name of the component (helius, quicknode, jupiter, dexscreener)
        integration: ConnectionPoolIntegration instance
        api_func: The API function to call
        *args: Arguments to pass to the API function
        **kwargs: Keyword arguments to pass to the API function

    Returns:
        Result of the API call
    """
    logger = get_logger(f"APIWrapper-{component}")
    start_time = time()

    try:
        # Call the API function
        result = api_func(*args, **kwargs)

        # Record successful request
        response_time = time() - start_time
        integration.record_api_request(component, True, response_time)

        logger.debug(f"API call successful for {component}",
                    response_time=response_time)

        return result

    except Exception as e:
        # Record failed request
        response_time = time() - start_time
        integration.record_api_request(component, False, response_time)

        logger.error(f"API call failed for {component}",
                    error=str(e),
                    response_time=response_time)

        # Re-raise the exception
        raise e

fn wrap_async_api_call(component: String, integration: ConnectionPoolIntegration, api_func, *args, **kwargs):
    """
    Wrap an async API call with connection pool monitoring

    Args:
        component: Name of the component (helius, quicknode, jupiter, dexscreener)
        integration: ConnectionPoolIntegration instance
        api_func: The async API function to call
        *args: Arguments to pass to the API function
        **kwargs: Keyword arguments to pass to the API function

    Returns:
        Coroutine that wraps the API call
    """
    logger = get_logger(f"AsyncAPIWrapper-{component}")

    async def wrapped_call():
        start_time = time()

        try:
            # Call the async API function
            result = await api_func(*args, **kwargs)

            # Record successful request
            response_time = time() - start_time
            integration.record_api_request(component, True, response_time)

            logger.debug(f"Async API call successful for {component}",
                        response_time=response_time)

            return result

        except Exception as e:
            # Record failed request
            response_time = time() - start_time
            integration.record_api_request(component, False, response_time)

            logger.error(f"Async API call failed for {component}",
                        error=str(e),
                        response_time=response_time)

            # Re-raise the exception
            raise e

    return wrapped_call()

class APICallWrapper:
    """
    A wrapper class for API calls that includes monitoring
    """
    var component: String
    var integration: ConnectionPoolIntegration
    var logger: Any

    fn __init__(component: String, integration: ConnectionPoolIntegration):
        self.component = component
        self.integration = integration
        self.logger = get_logger(f"APICallWrapper-{component}")

    def call(self, api_func, *args, **kwargs):
        """
        Wrap a synchronous API call
        """
        return wrap_api_call(self.component, self.integration, api_func, *args, **kwargs)

    async def call_async(self, api_func, *args, **kwargs):
        """
        Wrap an asynchronous API call
        """
        return await wrap_async_api_call(self.component, self.integration, api_func, *args, **kwargs)

    def record_request_result(self, success: Bool, response_time: Float = 0.0):
        """
        Manually record a request result

        Args:
            success: Whether the request was successful
            response_time: Response time in seconds
        """
        self.integration.record_api_request(self.component, success, response_time)