using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Security.Authentication;
using Sidey.Core.Localization;

namespace Sidey.Infrastructure.Realtime;

internal static class RealtimeUserErrorMessage
{
    public static string From(Exception exception)
    {
        for (Exception? current = exception; current is not null; current = current.InnerException)
        {
            switch (current)
            {
                case RealtimeSubscriptionException
                {
                    FailureKind: RealtimeSubscriptionFailureKind.Authorization,
                }:
                    return I18n.Get("connection.error.access_required");
                case RealtimeSubscriptionException
                {
                    FailureKind: RealtimeSubscriptionFailureKind.Capacity,
                }:
                    return I18n.Get("connection.error.busy");
                case RealtimeSubscriptionException
                {
                    FailureKind: RealtimeSubscriptionFailureKind.Configuration,
                }:
                    return I18n.Get("connection.error.configuration_unavailable");
                case RealtimeSubscriptionException:
                    return I18n.Get("connection.error.service_unavailable");
                case HttpRequestException { StatusCode: HttpStatusCode.TooManyRequests }:
                    return I18n.Get("connection.error.busy");
                case HttpRequestException { StatusCode: HttpStatusCode.Unauthorized }:
                    return I18n.Get("connection.error.access_required");
                case HttpRequestException
                {
                    StatusCode: HttpStatusCode.BadRequest or HttpStatusCode.Forbidden,
                }:
                    return I18n.Get("connection.error.configuration_unavailable");
                case UnauthorizedAccessException:
                    return I18n.Get("connection.error.access_required");
                case SocketException socketException
                    when IsLocalNetworkFailure(socketException.SocketErrorCode):
                    return I18n.Get("connection.error.network_unavailable");
                case AuthenticationException:
                    return I18n.Get("connection.error.secure_connection_failed");
            }
        }

        return I18n.Get("connection.error.service_unavailable");
    }

    public static bool IsExpectedLocalAbort(Exception exception)
    {
        for (Exception? current = exception; current is not null; current = current.InnerException)
        {
            if (current is SocketException { SocketErrorCode: SocketError.OperationAborted })
            {
                return true;
            }
        }
        return false;
    }

    private static bool IsLocalNetworkFailure(SocketError error) => error is
        SocketError.HostNotFound or SocketError.NoData or SocketError.TryAgain
        or SocketError.NetworkDown or SocketError.NetworkUnreachable
        or SocketError.HostDown or SocketError.HostUnreachable;
}
